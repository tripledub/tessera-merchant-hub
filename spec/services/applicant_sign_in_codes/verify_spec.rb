# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantSignInCodes::Verify do
  let(:applicant) { create(:applicant) }
  let(:email) { "invitee@example.com" }
  let!(:record) { create(:applicant_sign_in_code, applicant: applicant, email: email, code: "482913") }

  def verify(code, address: email)
    described_class.call(applicant: applicant, email: address, code: code)
  end

  describe "the right code" do
    it "is verified once and consumed" do
      result = verify("482913")

      expect(result.status).to eq(:verified)
      expect(record.reload.consumed_at).to be_present
    end

    it "cannot be used a second time (replay)" do
      verify("482913")

      expect(verify("482913").status).to eq(:used)
    end

    it "tolerates the address being typed in another case" do
      expect(verify("482913", address: " Invitee@Example.com ").status).to eq(:verified)
    end

    it "does not create a user, and returns none when there is no account yet" do
      expect { verify("482913") }.not_to change(ApplicantUser, :count)
      expect(described_class.call(applicant: applicant, email: email, code: "482913").applicant_user).to be_nil
    end

    it "confirms an existing unconfirmed user for that address and returns it" do
      user = create(:applicant_user, :unconfirmed, applicant: applicant, email: email)

      result = verify("482913")

      expect(result.applicant_user).to eq(user)
      expect(user.reload).to be_confirmed
    end

    it "leaves an already confirmed user alone" do
      user = create(:applicant_user, applicant: applicant, email: email, confirmed_at: 3.days.ago)

      expect { verify("482913") }.not_to change { user.reload.confirmed_at }
    end
  end

  describe "a wrong code" do
    it "says how many attempts are left, counting down" do
      results = Array.new(4) { verify("000000") }

      expect(results.map(&:status)).to all(eq(:wrong))
      expect(results.map(&:attempts_left)).to eq([ 4, 3, 2, 1 ])
      expect(record.reload.attempts).to eq(4)
    end

    it "locks the code on the fifth wrong attempt" do
      4.times { verify("000000") }

      result = verify("000000")

      expect(result.status).to eq(:locked)
      expect(record.reload).to have_attributes(attempts: 5, invalidated_at: be_present)
    end

    it "stays locked even when the right code is then entered" do
      5.times { verify("000000") }

      expect(verify("482913").status).to eq(:locked)
      expect(record.reload.consumed_at).to be_nil
    end

    it "counts malformed input as an attempt too" do
      [ "", "12345", "abcdef", nil ].each { |code| expect(verify(code).status).to eq(:wrong) }

      expect(record.reload.attempts).to eq(4)
    end

    it "does not create or confirm a user" do
      user = create(:applicant_user, :unconfirmed, applicant: applicant, email: email)

      verify("000000")

      expect(user.reload).not_to be_confirmed
    end
  end

  describe "expiry" do
    it "reports an expired code without using up an attempt" do
      travel_to(11.minutes.from_now) do
        expect(verify("482913").status).to eq(:expired)
      end

      expect(record.reload.attempts).to eq(0)
    end

    it "is still valid just before it expires" do
      travel_to(9.minutes.from_now) { expect(verify("482913").status).to eq(:verified) }
    end
  end

  describe "a newer code" do
    it "is the only one that counts: an older code entered after it is a wrong attempt" do
      newer = create(:applicant_sign_in_code, applicant: applicant, email: email, code: "111222", created_at: 1.minute.from_now)
      record.update!(invalidated_at: Time.current)

      older_result = nil
      travel_to(2.minutes.from_now) { older_result = verify("482913") }
      newer_result = nil
      travel_to(2.minutes.from_now) { newer_result = verify("111222") }

      expect(older_result.status).to eq(:wrong)
      expect(newer_result.status).to eq(:verified)
      expect(newer.reload.attempts).to eq(2)
    end
  end

  describe "nothing to verify" do
    it "says there is no code for an address that never asked for one" do
      expect(verify("482913", address: "nobody@example.com").status).to eq(:none)
    end

    it "keeps one applicant's codes away from another's" do
      other = create(:applicant)

      expect(described_class.call(applicant: other, email: email, code: "482913").status).to eq(:none)
    end
  end

  describe "logging" do
    before { allow(SecurityEventLogger).to receive(:log_event) }

    it "logs each outcome with the code id, attempts and a fingerprint of the address, never the code" do
      verify("000000")
      verify("482913")

      expect(SecurityEventLogger).to have_received(:log_event).with(
        event: "portal.sign_in_code.wrong", code_id: record.id, attempts: 1, email_fingerprint: SecurityEventLogger.fingerprint(email)
      )
      expect(SecurityEventLogger).to have_received(:log_event).with(
        event: "portal.sign_in_code.verified", code_id: record.id, attempts: 2, email_fingerprint: SecurityEventLogger.fingerprint(email)
      )
      expect(SecurityEventLogger).not_to have_received(:log_event).with(hash_including(code: anything))
    end

    it "logs expired and locked outcomes" do
      travel_to(11.minutes.from_now) { verify("482913") }
      expect(SecurityEventLogger).to have_received(:log_event).with(hash_including(event: "portal.sign_in_code.expired"))
    end

    it "never writes the code, right or wrong, to the Rails log" do
      logged = +""
      allow(Rails.logger).to receive(:warn) { |message| logged << message.to_s }
      allow(SecurityEventLogger).to receive(:log_event).and_call_original

      verify("000000")
      verify("482913")

      expect(logged).not_to include("482913")
      expect(logged).not_to include("000000")
    end
  end
end
