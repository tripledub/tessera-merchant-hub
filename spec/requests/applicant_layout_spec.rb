# frozen_string_literal: true

require "rails_helper"

# MH-394: every applicant surface renders in the Kynetic applicant layout:
# light only, the real logo, our own font, and no call to Google Fonts. The
# admin side keeps Outfit (loaded from Google by the admin layout only) and its
# dark-mode toggle.
RSpec.describe "Applicant layout", type: :request do
  shared_examples "an applicant page" do
    it "uses the Kynetic font and the real logo" do
      subject_page

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("font-kynetic")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("img[src*='kynetic-icon']")).to be_present
      expect(document.css("a").map(&:text).join(" ")).to include("Kynetic")
    end

    it "is light only, with no dark-mode toggle or script" do
      subject_page

      expect(response.body).not_to include('data-controller="dark-mode"')
      expect(response.body).not_to include("darkMode")
      expect(response.body).not_to include("classList.add(\"dark\")")
    end

    it "makes no request to Google Fonts" do
      subject_page

      expect(response.body).not_to include("fonts.googleapis.com")
      expect(response.body).not_to include("fonts.gstatic.com")
    end

    it "does not render with a dark class on the document element" do
      subject_page

      expect(Nokogiri::HTML(response.body).at_css("html")["class"].to_s).not_to include("dark")
    end
  end

  let(:applicant_user) { create(:applicant_user) }

  context "when signed out" do
    describe "sign in" do
      subject(:subject_page) { get new_applicant_user_session_path }

      it_behaves_like "an applicant page"
    end

    describe "password reset request" do
      subject(:subject_page) { get new_applicant_user_password_path }

      it_behaves_like "an applicant page"
    end

    describe "registration from an invitation" do
      subject(:subject_page) { get new_applicant_user_registration_path(invitation_token: token) }

      let(:token) do
        _invitation, issued_token = ApplicantInvitation.issue!(
          applicant: create(:applicant), email: "invited@example.com", invited_by: create(:user, :psp_admin)
        )
        issued_token
      end

      it_behaves_like "an applicant page"
    end
  end

  context "when signed in" do
    before { sign_in applicant_user, scope: :applicant_user }

    describe "dashboard" do
      subject(:subject_page) { get portal_root_path }

      it_behaves_like "an applicant page"

      it "shows the signed-in email and a sign out link in the header" do
        subject_page

        header = Capybara.string(response.body).find("header")
        expect(header).to have_text(applicant_user.email)
        expect(header).to have_link("Sign out")
      end

      it "uses the narrow content width" do
        subject_page

        expect(response.body).to include("max-w-[720px]")
      end
    end

    describe "application form" do
      subject(:subject_page) { get portal_application_path }

      it_behaves_like "an applicant page"

      it "uses the wide content width" do
        subject_page

        expect(response.body).to include("max-w-[1120px]")
      end
    end

    describe "onboarding chat" do
      subject(:subject_page) { get portal_onboarding_path }

      it_behaves_like "an applicant page"

      it "uses the narrow content width" do
        subject_page

        expect(response.body).to include("max-w-[720px]")
      end
    end
  end

  describe "admin pages" do
    it "keeps Outfit loaded from Google, and the dark-mode toggle, on the admin sign-in page" do
      get new_user_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fonts.googleapis.com/css2?family=Outfit")
      expect(response.body).to include("font-outfit")
      expect(response.body).to include('data-controller="dark-mode"')
      expect(response.body).not_to include("font-kynetic")
    end

    it "keeps Outfit loaded from Google in the authenticated admin shell" do
      sign_in create(:user, :psp_admin)

      get authenticated_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fonts.googleapis.com/css2?family=Outfit")
      expect(response.body).to include("font-outfit")
      expect(response.body).not_to include("font-kynetic")
    end
  end
end
