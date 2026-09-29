# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantInvitation, type: :model do
  subject(:invitation) { build(:applicant_invitation) }

  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to belong_to(:invited_by).class_name("User") }
  it { is_expected.to belong_to(:claimed_by).class_name("ApplicantUser").optional }

  it { is_expected.to validate_presence_of(:email) }

  it "normalizes the intended email address" do
    invitation.email = "  APPLICANT@EXAMPLE.COM "

    invitation.validate

    expect(invitation.email).to eq("applicant@example.com")
  end

  describe ".issue!" do
    it "returns a bearer token while persisting only its digest" do
      record, token = described_class.issue!(
        applicant: create(:applicant),
        email: "applicant@example.com",
        invited_by: create(:user, :psp_admin)
      )

      expect(token).to be_present
      expect(record.token_digest).to eq(Digest::SHA256.hexdigest(token))
      expect(record.token_digest).not_to eq(token)
      expect(described_class.find_usable_by_token(token)).to eq(record)
    end
  end

  describe ".find_usable_by_token" do
    it "does not return claimed or revoked invitations" do
      claimed, claimed_token = described_class.issue!(
        applicant: create(:applicant), email: "claimed@example.com", invited_by: create(:user, :psp_admin)
      )
      revoked, revoked_token = described_class.issue!(
        applicant: create(:applicant), email: "revoked@example.com", invited_by: create(:user, :psp_admin)
      )
      claimed.update!(claimed_at: Time.current)
      revoked.update!(revoked_at: Time.current)

      expect(described_class.find_usable_by_token(claimed_token)).to be_nil
      expect(described_class.find_usable_by_token(revoked_token)).to be_nil
    end
  end

  describe "#claim!" do
    it "records the invited applicant user and claim time" do
      invitation, = described_class.issue!(
        applicant: create(:applicant), email: "applicant@example.com", invited_by: create(:user, :psp_admin)
      )
      applicant_user = build(:applicant_user, applicant: invitation.applicant, email: invitation.email)

      invitation.claim!(applicant_user)

      expect(invitation).to have_attributes(claimed_by: applicant_user)
      expect(invitation.claimed_at).to be_present
    end

    it "rejects a user for another applicant" do
      invitation = create(:applicant_invitation)

      expect { invitation.claim!(build(:applicant_user)) }.to raise_error(ApplicantInvitation::NotClaimable)
    end
  end
end
