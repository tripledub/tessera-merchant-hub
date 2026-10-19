# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantInvitationMailer, type: :mailer do
  describe "#invite" do
    let(:applicant) { create(:applicant, name: "Evergreen Retail Ltd") }
    let(:invitation) { create(:applicant_invitation, applicant: applicant, email: "new.applicant@example.com") }
    let(:mail) { described_class.invite(invitation, "https://uat.kynetic.id/portal/invitations/abc123") }

    it "addresses the applicant and names them in the subject" do
      expect(mail.to).to eq([ "new.applicant@example.com" ])
      expect(mail.subject).to include("Evergreen Retail Ltd")
    end

    it "includes the registration link in both bodies" do
      expect(mail.html_part.body.to_s).to include("https://uat.kynetic.id/portal/invitations/abc123")
      expect(mail.text_part.body.to_s).to include("https://uat.kynetic.id/portal/invitations/abc123")
    end

    it "inlines the mailer stylesheet into the delivered HTML via premailer-rails" do
      mail.deliver_now

      html = ActionMailer::Base.deliveries.last.html_part.body.to_s

      expect(html).to include('style="').and include("background-color: #465fff")
      expect(html).not_to include("<link")
    end
  end

  # MH-412: a renewal is sent in the background, and Solid Queue stores a job's
  # arguments in the queue database, so the link travels encrypted.
  describe "#renewal" do
    let(:applicant) { create(:applicant, name: "Evergreen Retail Ltd") }
    let(:invitation) { create(:applicant_invitation, applicant: applicant, email: "new.applicant@example.com") }
    let(:link) { "https://uat.kynetic.id/portal/invitations/abc123" }
    let(:purpose) { ApplicantInvitation::RENEWAL_MAIL_PURPOSE }
    let(:encrypted) { ShortLivedSecret.encrypt(link, purpose: purpose, expires_in: ApplicantInvitation::RENEWAL_MAIL_LIFETIME) }
    let(:mail) { described_class.renewal(invitation, encrypted) }

    it "sends the same email as an invitation, with the decrypted link, to the invited address" do
      expect(mail.to).to eq([ "new.applicant@example.com" ])
      expect(mail.subject).to eq(described_class.invite(invitation, link).subject)
      expect(mail.subject).to include("Evergreen Retail Ltd")
      expect([ mail.html_part.body.to_s, mail.text_part.body.to_s ]).to all(include(link))
    end

    it "does not contain the encrypted value" do
      expect(mail.text_part.body.to_s).not_to include(encrypted)
    end

    it "sends nothing, and does not raise, once the encrypted link has expired" do
      encrypted
      travel_to(ApplicantInvitation::RENEWAL_MAIL_LIFETIME.from_now + 1.minute) do
        expect { mail.deliver_now }.not_to raise_error
      end

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "sends nothing for a value that was altered, made for another purpose, or is not a link at all" do
      other = ShortLivedSecret.encrypt(link, purpose: :something_else, expires_in: 15.minutes)

      [ encrypted.reverse, other, "not encrypted", link, nil ].each do |value|
        expect { described_class.renewal(invitation, value).deliver_now }.not_to raise_error
      end

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "background delivery" do
    it "keeps the delivery job's arguments, which can include one-time links and tokens, out of the log" do
      expect(described_class.delivery_job).to eq(ActionMailer::MailDeliveryJob)
      expect(ActionMailer::MailDeliveryJob.log_arguments).to be(false)
    end
  end
end
