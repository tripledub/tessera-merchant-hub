# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding authentication", type: :request do
  describe "GET /portal/sign_up" do
    it "renders the dark mode toggle" do
      get new_applicant_user_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="dark-mode"')
      expect(response.body).to include('aria-label="Toggle dark mode"')
    end
  end

  describe "POST /portal (sign up)" do
    let(:sign_up_params) do
      {
        applicant_user: {
          first_name: "Jane",
          last_name: "Doe",
          email: "jane.doe@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        }
      }
    end

    it "creates an ApplicantUser and associated Applicant" do
      expect {
        post applicant_user_registration_path, params: sign_up_params
      }.to change(ApplicantUser, :count).by(1)
        .and change(Applicant, :count).by(1)

      expect(response).to redirect_to(portal_root_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "sets the applicant name from first and last name" do
      post applicant_user_registration_path, params: sign_up_params
      applicant = ApplicantUser.last.applicant
      expect(applicant.name).to eq("Jane Doe")
    end

    it "rejects sign up with missing password confirmation" do
      sign_up_params[:applicant_user][:password_confirmation] = ""
      post applicant_user_registration_path, params: sign_up_params
      expect(response).to have_http_status(:unprocessable_entity)
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
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /portal/sign_out" do
    let!(:applicant_user) { create(:applicant_user) }

    it "signs out the applicant user" do
      sign_in applicant_user, scope: :applicant_user
      delete destroy_applicant_user_session_path
      expect(response).to redirect_to(root_path)
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
  end
end
