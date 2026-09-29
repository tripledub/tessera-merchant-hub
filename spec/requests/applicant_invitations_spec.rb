# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Applicant invitations", type: :request do
  let(:applicant) { create(:applicant, contact_email: "applicant@example.com") }

  describe "GET /applicants/:applicant_id/applicant_invitations/new" do
    it "allows a PSP admin to prepare an invitation" do
      sign_in create(:user, :psp_admin)

      get new_applicant_applicant_invitation_path(applicant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("applicant@example.com")
    end

    it "forbids PSP support users" do
      sign_in create(:user, :psp_support)

      get new_applicant_applicant_invitation_path(applicant)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /applicants/:applicant_id/applicant_invitations" do
    it "creates an invitation and displays its one-time URL" do
      sign_in create(:user, :psp_admin)

      expect {
        post applicant_applicant_invitations_path(applicant), params: {
          applicant_invitation: { email: "new.applicant@example.com" }
        }
      }.to change(ApplicantInvitation, :count).by(1)

      invitation = ApplicantInvitation.last
      expect(invitation.invited_by).to eq(controller.current_user)
      expect(response).to have_http_status(:created)
      expect(response.body).to include("new.applicant@example.com")
      expect(response.body).to include("/portal/invitations/")
      expect(response.body).not_to include(invitation.token_digest)
    end

    it "does not create an invitation with an invalid email" do
      sign_in create(:user, :psp_admin)

      expect {
        post applicant_applicant_invitations_path(applicant), params: {
          applicant_invitation: { email: "not-an-email" }
        }
      }.not_to change(ApplicantInvitation, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /portal/invitations/:token" do
    it "accepts an unclaimed invitation without exposing applicant data" do
      invitation, token = ApplicantInvitation.issue!(
        applicant: applicant, email: applicant.contact_email, invited_by: create(:user, :psp_admin)
      )

      get portal_invitation_path(token)

      expect(response).to redirect_to(new_applicant_user_registration_path(invitation_token: token))
      expect(response.body).not_to include(applicant.name)
      expect(response.body).not_to include(invitation.email)
    end

    it "returns the same response for unknown and unusable tokens" do
      invitation, token = ApplicantInvitation.issue!(
        applicant: applicant, email: applicant.contact_email, invited_by: create(:user, :psp_admin)
      )
      invitation.update!(revoked_at: Time.current)

      get portal_invitation_path(token)
      unusable_status = response.status
      get portal_invitation_path("unknown-token")

      expect(response.status).to eq(unusable_status).and eq(404)
    end
  end
end
