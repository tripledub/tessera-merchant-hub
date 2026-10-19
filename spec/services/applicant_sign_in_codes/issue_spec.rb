# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantSignInCodes::Issue do
  include ActiveJob::TestHelper

  let(:applicant) { create(:applicant) }
  let(:email) { "invitee@example.com" }

  def issue(**options)
    described_class.call(applicant: applicant, email: email, **options)
  end

  # The only place the plaintext code exists is the delivered email.
  def delivered_code
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end

  it "stores a keyed digest of the code, never the code, and sends the code by email" do
    result = nil
    perform_enqueued_jobs { result = issue }

    expect(result.status).to eq(:sent)
    record = ApplicantSignInCode.last
    expect(record).to have_attributes(applicant_id: applicant.id, email: email, attempts: 0, consumed_at: nil, invalidated_at: nil)
    expect(record.expires_at).to be_within(5.seconds).of(10.minutes.from_now)
    expect(ActionMailer::Base.deliveries.last.to).to eq([ email ])
    expect(delivered_code).to be_present
    expect(record.matches?(delivered_code)).to be(true)
    expect(record.attributes.values.map(&:to_s)).not_to include(delivered_code)
  end

  it "normalises the address" do
    described_class.call(applicant: applicant, email: "  Invitee@Example.COM ")

    expect(ApplicantSignInCode.last.email).to eq("invitee@example.com")
  end

  it "queues the email without the plaintext code in its arguments" do
    allow(ApplicantSignInCode).to receive(:generate_code).and_return("482913")

    expect { issue }.to have_enqueued_mail(ApplicantSignInCodeMailer, :code)

    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.to_json).not_to include("482913")
  end

  it "remembers the invitation and an existing user for that address" do
    invitation = create(:applicant_invitation, applicant: applicant, email: email)
    user = create(:applicant_user, applicant: applicant, email: email)

    issue(invitation: invitation)

    expect(ApplicantSignInCode.last).to have_attributes(applicant_invitation_id: invitation.id, applicant_user_id: user.id)
  end

  it "supersedes the earlier code" do
    issue
    first = ApplicantSignInCode.last

    travel_to(31.seconds.from_now) { issue }

    expect(first.reload.invalidated_at).to be_present
    expect(ApplicantSignInCode.order(:created_at).last.invalidated_at).to be_nil
  end

  describe "limits, per applicant and address" do
    it "asks for 30 seconds between codes, and says how long is left" do
      issue

      result = nil
      expect { travel_to(10.seconds.from_now) { result = issue } }.not_to change(ApplicantSignInCode, :count)

      expect(result.status).to eq(:too_soon)
      expect(result.retry_after).to be_between(19, 21)
    end

    it "allows the next code after 30 seconds" do
      issue

      travel_to(31.seconds.from_now) { expect(issue.status).to eq(:sent) }
    end

    it "allows five codes an hour, then says how long to wait" do
      5.times { |index| travel_to((index * 31).seconds.from_now) { issue } }

      result = nil
      travel_to((5 * 31).seconds.from_now) { result = issue }

      expect(result.status).to eq(:rate_limited)
      expect(result.retry_after).to be_between(3_300, 3_600)
      expect(ApplicantSignInCode.count).to eq(5)
    end

    it "lets the hour pass" do
      5.times { |index| travel_to((index * 31).seconds.from_now) { issue } }

      travel_to(61.minutes.from_now) { expect(issue.status).to eq(:sent) }
    end

    it "allows twenty codes a day" do
      20.times do |index|
        create(:applicant_sign_in_code, applicant: applicant, email: email, created_at: (index + 1).hours.ago + 5.minutes)
      end

      result = issue

      expect(result.status).to eq(:rate_limited)
      expect(result.retry_after).to be > 0
    end

    it "keeps the limits separate for another address and another applicant" do
      5.times { |index| travel_to((index * 31).seconds.from_now) { issue } }

      travel_to((5 * 31).seconds.from_now) do
        expect(described_class.call(applicant: applicant, email: "someone.else@example.com").status).to eq(:sent)
        expect(described_class.call(applicant: create(:applicant), email: email).status).to eq(:sent)
      end
    end
  end

  describe "logging" do
    before { allow(SecurityEventLogger).to receive(:log_event) }

    it "logs that a code was issued, by id and a fingerprint of the address, never the code" do
      allow(ApplicantSignInCode).to receive(:generate_code).and_return("482913")

      issue

      expect(SecurityEventLogger).to have_received(:log_event).with(
        event: "portal.sign_in_code.issued",
        code_id: ApplicantSignInCode.last.id,
        email_fingerprint: SecurityEventLogger.fingerprint(email)
      )
      expect(SecurityEventLogger).not_to have_received(:log_event).with(hash_including(code: anything))
    end

    it "logs why a request was refused" do
      issue
      travel_to(5.seconds.from_now) { issue }

      expect(SecurityEventLogger).to have_received(:log_event).with(
        hash_including(event: "portal.sign_in_code.rate_limited", reason: :too_soon, email_fingerprint: SecurityEventLogger.fingerprint(email))
      )
    end
  end
end
