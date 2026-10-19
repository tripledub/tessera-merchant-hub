# frozen_string_literal: true

require "rails_helper"

# MH-406: the stand-in for a code that does not exist. For an address with no
# account it must count down, lock, expire and refuse to resend exactly as the
# real code service does, from numbers kept in the visitor's own session.
RSpec.describe ApplicantSignInCodes::Decoy do
  let(:now) { Time.zone.parse("2026-10-19 12:00:00") }
  let(:sent_at) { [ now.to_i ] }

  def status(attempts: 0, sent: sent_at, at: now)
    described_class.status(attempts: attempts, sent_at: sent, now: at)
  end

  describe ".status" do
    it "is active, with the seconds until another may be sent" do
      expect(status(at: now + 10.seconds)).to have_attributes(state: :active, resend_in: 20)
      expect(status(at: now + 31.seconds)).to have_attributes(state: :active, resend_in: 0)
    end

    it "is locked after five attempts, and expired after ten minutes" do
      expect(status(attempts: ApplicantSignInCode::MAX_ATTEMPTS).state).to eq(:locked)
      expect(status(at: now + 10.minutes + 1.second).state).to eq(:expired)
    end

    it "reports locked before expired, as the real service does" do
      expect(status(attempts: 5, at: now + 11.minutes).state).to eq(:locked)
    end
  end

  describe ".verify" do
    def verify(code = "123456", attempts: 0, at: now + 5.seconds)
      described_class.verify(attempts: attempts, sent_at: sent_at, code: code, now: at)
    end

    it "never accepts a code, and counts the attempts down: 4, 3, 2, 1, then locked" do
      attempts = 0
      outcomes = 5.times.map do
        outcome = verify(attempts: attempts)
        attempts = outcome.attempts
        [ outcome.status, outcome.attempts_left ]
      end

      expect(outcomes).to eq([ [ :wrong, 4 ], [ :wrong, 3 ], [ :wrong, 2 ], [ :wrong, 1 ], [ :locked, nil ] ])
    end

    it "keeps saying locked once locked, even for what would be the right code" do
      expect(verify("123456", attempts: 5)).to have_attributes(status: :locked, attempts: 5)
    end

    it "says expired after ten minutes without using an attempt" do
      expect(verify(attempts: 2, at: now + 11.minutes)).to have_attributes(status: :expired, attempts: 2)
    end

    it "does the keyed comparison work of a real check" do
      allow(ApplicantSignInCode).to receive(:digest_for).and_call_original

      verify

      expect(ApplicantSignInCode).to have_received(:digest_for).once
    end
  end

  describe ".resend" do
    def resend(sent: sent_at, at: now + 31.seconds)
      described_class.resend(sent_at: sent, now: at)
    end

    it "is too soon inside the thirty-second gap, with the seconds to wait" do
      outcome = resend(at: now + 10.seconds)

      expect(outcome).to have_attributes(status: :too_soon, retry_after: 20, sent_at: sent_at)
    end

    it "sends a new one after the gap, remembering when and starting the attempts again" do
      outcome = resend

      expect(outcome).to have_attributes(status: :sent, attempts: 0)
      expect(outcome.sent_at).to eq(sent_at + [ (now + 31.seconds).to_i ])
    end

    it "stops at ten an hour and twenty a day, as the real service does" do
      hourly = Array.new(10) { |i| (now - 50.minutes + (i * 2).minutes).to_i }
      expect(resend(sent: hourly, at: now)).to have_attributes(status: :rate_limited)
      expect(resend(sent: hourly, at: now).retry_after).to be_positive

      daily = Array.new(20) { |i| (now - 23.hours + (i * 40).minutes).to_i }
      expect(resend(sent: daily, at: now)).to have_attributes(status: :rate_limited)
    end

    it "forgets sends older than a day" do
      old = Array.new(20) { (now - 2.days).to_i }

      expect(resend(sent: old + [ (now - 1.minute).to_i ])).to have_attributes(status: :sent)
      expect(resend(sent: old).sent_at.size).to eq(1)
    end
  end
end
