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
    it "creates an invitation, emails it, and displays its one-time URL as a backup" do
      sign_in create(:user, :psp_admin)

      expect {
        post applicant_applicant_invitations_path(applicant), params: {
          applicant_invitation: { email: "new.applicant@example.com" }
        }
      }.to change(ApplicantInvitation, :count).by(1).and change(ActionMailer::Base.deliveries, :count).by(1)

      invitation = ApplicantInvitation.last
      expect(invitation.invited_by).to eq(controller.current_user)
      expect(response).to have_http_status(:created)
      expect(response.body).to include("An Invite has been sent to #{applicant.name} (new.applicant@example.com)")
      expect(response.body).to include("/portal/invitations/")
      expect(response.body).not_to include(invitation.token_digest)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "new.applicant@example.com" ])

      page = Capybara.string(response.body)
      url_field = page.find("[data-clipboard-target='source']")
      expect(url_field["class"]).to include("dark:text-white/90")
      expect(url_field["value"]).to include("/portal/invitations/")
      expect(page).to have_css("[data-action='clipboard#copy'][aria-label='Copy invitation link']")
      expect(page).to have_no_css("button.btn-primary")
    end

    it "still creates the invitation and shows the manual link when email delivery fails" do
      sign_in create(:user, :psp_admin)
      allow(ApplicantInvitationMailer).to receive(:invite).and_raise(Net::SMTPFatalError.new("mailbox unavailable"))

      expect {
        post applicant_applicant_invitations_path(applicant), params: {
          applicant_invitation: { email: "new.applicant@example.com" }
        }
      }.to change(ApplicantInvitation, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(Capybara.string(response.body).text).to include("Couldn't send the invitation email automatically")
      expect(response.body).to include("/portal/invitations/")
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

    it "returns the same not-found response for an expired token" do
      _invitation, token = ApplicantInvitation.issue!(
        applicant: applicant, email: applicant.contact_email, invited_by: create(:user, :psp_admin)
      )
      travel_to(ApplicantInvitation::EXPIRY.from_now + 1.minute) do
        get portal_invitation_path(token)
      end

      expect(response).to have_http_status(:not_found)
    end

    it "rate limits repeated invitation-token probes" do
      store = Portal::InvitationsController.portal_rate_limit_store
      store.write("rate-limit:portal/invitations:127.0.0.1", 20, expires_in: 1.minute)

      get portal_invitation_path("unknown-token")

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
