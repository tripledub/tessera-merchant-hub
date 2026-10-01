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

    it "backfills a blank applicant contact_email with the invited address" do
      applicant = create(:applicant, contact_email: nil)

      described_class.issue!(applicant: applicant, email: "  APPLICANT@EXAMPLE.COM ", invited_by: create(:user, :psp_admin))

      expect(applicant.reload.contact_email).to eq("applicant@example.com")
    end

    it "does not overwrite an existing applicant contact_email" do
      applicant = create(:applicant, contact_email: "existing@example.com")

      described_class.issue!(applicant: applicant, email: "new@example.com", invited_by: create(:user, :psp_admin))

      expect(applicant.reload.contact_email).to eq("existing@example.com")
    end

    it "sets an expiry in the future" do
      record, = described_class.issue!(
        applicant: create(:applicant), email: "applicant@example.com", invited_by: create(:user, :psp_admin)
      )

      expect(record.expires_at).to be_within(1.second).of(described_class::EXPIRY.from_now)
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

    it "does not return an expired invitation" do
      invitation, token = described_class.issue!(
        applicant: create(:applicant), email: "applicant@example.com", invited_by: create(:user, :psp_admin)
      )
      invitation.update!(expires_at: 1.minute.ago)

      expect(described_class.find_usable_by_token(token)).to be_nil
    end

    it "returns an invitation with no expiry set (e.g. issued before expiry was introduced)" do
      invitation, token = described_class.issue!(
        applicant: create(:applicant), email: "applicant@example.com", invited_by: create(:user, :psp_admin)
      )
      invitation.update!(expires_at: nil)

      expect(described_class.find_usable_by_token(token)).to eq(invitation)
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
