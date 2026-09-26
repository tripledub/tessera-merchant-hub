# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding authentication", type: :request do
  describe "GET /portal/sign_up" do
    it "does not allow open registration" do
      get new_applicant_user_registration_path

      expect(response).to have_http_status(:not_found)
    end

    it "renders registration for a usable invitation with a fixed email address" do
      invitation, token = ApplicantInvitation.issue!(
        applicant: create(:applicant), email: "invited@example.com", invited_by: create(:user, :psp_admin)
      )

      get new_applicant_user_registration_path(invitation_token: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="dark-mode"')
      expect(response.body).to include('aria-label="Toggle dark mode"')
      email = Nokogiri::HTML(response.body).at_css("input[name='applicant_user[email]']")
      expect(email["value"]).to eq(invitation.email)
      expect(email.attribute("readonly")).to be_present
    end
  end

  describe "POST /portal (sign up)" do
    let(:applicant) { create(:applicant, name: "Test Company") }
    let(:invitation_and_token) do
      ApplicantInvitation.issue!(
        applicant: applicant, email: "invited@example.com", invited_by: create(:user, :psp_admin)
      )
    end
    let(:invitation) { invitation_and_token.first }
    let(:token) { invitation_and_token.second }
    let(:sign_up_params) do
      {
        invitation_token: token,
        applicant_user: {
          first_name: "Jane",
          last_name: "Doe",
          email: "attacker@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        }
      }
    end

    it "creates an unconfirmed user for the invited applicant and claims the invitation" do
      invitation
      applicant_count = Applicant.count

      expect {
        post applicant_user_registration_path, params: sign_up_params
      }.to change(ApplicantUser, :count).by(1)
      expect(Applicant.count).to eq(applicant_count)

      applicant_user = ApplicantUser.last
      expect(applicant_user).to have_attributes(
        applicant: applicant,
        email: invitation.email,
        confirmed_at: nil
      )
      expect(applicant_user.confirmation_sent_at).to be_present
      expect(applicant_user.confirmation_token).to be_present
      expect(invitation.reload).to have_attributes(claimed_by: applicant_user)
      expect(invitation.claimed_at).to be_present
      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "rejects sign up with missing password confirmation" do
      sign_up_params[:applicant_user][:password_confirmation] = ""

      expect {
        post applicant_user_registration_path, params: sign_up_params
      }.not_to change(Applicant, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects sign up with missing applicant names without creating an Applicant" do
      sign_up_params[:applicant_user][:first_name] = ""
      sign_up_params[:applicant_user][:last_name] = ""

      expect {
        post applicant_user_registration_path, params: sign_up_params
      }.not_to change(Applicant, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects registration without a usable invitation" do
      sign_up_params[:invitation_token] = "unknown"

      expect {
        post applicant_user_registration_path, params: sign_up_params
      }.not_to change(ApplicantUser, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /portal/sign_in" do
    let!(:applicant_user) { create(:applicant_user, email: "user@example.com", password: "password123!") }

    it "signs in with valid credentials" do
      post new_applicant_user_session_path, params: {
        applicant_user: { email: "user@example.com", password: "password123!" }
      }
      expect(response).to redirect_to(portal_root_path)
    end

    it "rejects invalid credentials" do
      post new_applicant_user_session_path, params: {
        applicant_user: { email: "user@example.com", password: "wrong" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /portal/sign_out" do
    let!(:applicant_user) { create(:applicant_user) }

    it "signs out the applicant user" do
      sign_in applicant_user, scope: :applicant_user
      delete destroy_applicant_user_session_path
      expect(response).to redirect_to(new_applicant_user_session_path)
    end
  end

  describe "GET /portal (dashboard)" do
    it "redirects unauthenticated users to sign in" do
      get portal_root_path
      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "shows the dashboard for authenticated applicant users" do
      applicant_user = create(:applicant_user, first_name: "Alex")
      sign_in applicant_user, scope: :applicant_user
      get portal_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Welcome, Alex!")
    end

    it "does not allow an unconfirmed applicant user to sign in" do
      applicant_user = create(:applicant_user, :unconfirmed)

      post new_applicant_user_session_path, params: {
        applicant_user: { email: applicant_user.email, password: applicant_user.password }
      }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "allows an applicant user to sign in after confirming their email" do
      applicant_user = create(:applicant_user, :unconfirmed)
      applicant_user.confirm

      post new_applicant_user_session_path, params: {
        applicant_user: { email: applicant_user.email, password: applicant_user.password }
      }

      expect(response).to redirect_to(portal_root_path)
    end

    it "links authenticated applicant users to the onboarding chat" do
      applicant_user = create(:applicant_user)
      sign_in applicant_user, scope: :applicant_user

      get portal_root_path

      expect(response.body).to include("Continue KYC onboarding")
      expect(response.body).to include(portal_onboarding_path)
    end
  end
end
