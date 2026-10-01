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
  end
end
