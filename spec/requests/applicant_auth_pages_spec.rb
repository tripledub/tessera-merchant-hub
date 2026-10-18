# frozen_string_literal: true

require "rails_helper"

# MH-396: the five signed-out applicant pages (sign in, request reset, set new
# password, resend confirmation, register from an invitation) use the Kynetic
# primitives from MH-395 inside the applicant auth card, with no admin form
# classes, no dark variants, and the security line under the card.
RSpec.describe "Applicant auth pages", type: :request do
  let(:legacy_classes) { /(?<![\w-])(form-input|form-label|btn-primary|btn-secondary|text-brand-\d+|text-gray-\d+|dark:[a-z-]+)/ }

  def card_html
    Nokogiri::HTML(response.body).at_css(".kyn-card").to_html
  end

  shared_examples "a Kynetic auth page" do
    it "renders inside the Kynetic card with the security line under it" do
      subject_page

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".kyn-card h1")).to be_present
      expect(document.at_css(".kyn-card").next_element.text).to include(
        "Your information is encrypted and only used for compliance checks."
      )
    end

    it "uses no admin form classes or dark variants inside the card" do
      subject_page

      expect(card_html.scan(legacy_classes)).to be_empty
    end

    it "uses the Kynetic field, label and button primitives" do
      subject_page

      document = Nokogiri::HTML(response.body)
      expect(document.css(".kyn-card input.kyn-input")).not_to be_empty
      expect(document.css(".kyn-card label.kyn-label")).not_to be_empty
      expect(document.css(".kyn-card input[type=submit].kyn-btn-primary")).not_to be_empty
    end
  end

  describe "sign in" do
    subject(:subject_page) { get new_applicant_user_session_path }

    it_behaves_like "a Kynetic auth page"

    it "labels the password toggle and the remember-me row for assistive tech" do
      subject_page

      document = Nokogiri::HTML(response.body)
      toggle = document.at_css("button[data-action='password-toggle#toggle']")
      expect(toggle["aria-label"]).to eq("Show password")
      expect(toggle["aria-pressed"]).to eq("false")
      expect(document.at_css("label.kyn-check-label input.kyn-checkbox[name='applicant_user[remember_me]']")).to be_present
      expect(document.css(".kyn-card a.kyn-link").map(&:text)).to include("Forgot your password?")
    end
  end

  describe "request a password reset" do
    subject(:subject_page) { get new_applicant_user_password_path }

    it_behaves_like "a Kynetic auth page"
  end

  describe "resend confirmation" do
    subject(:subject_page) { get new_applicant_user_confirmation_path }

    it_behaves_like "a Kynetic auth page"
  end

  describe "set a new password" do
    subject(:subject_page) { get edit_applicant_user_password_path(reset_password_token: "token") }

    it_behaves_like "a Kynetic auth page"

    it "shows a mismatched confirmation as a described, invalid field error" do
      user = create(:applicant_user)
      # Not send_reset_password_instructions: the reset email template raises for
      # applicants today (MH-410), and these specs are about the page.
      token, encrypted = Devise.token_generator.generate(ApplicantUser, :reset_password_token)
      user.update!(reset_password_token: encrypted, reset_password_sent_at: Time.current)

      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: token, password: "new-password-1", password_confirmation: "different-1" }
      }

      document = Nokogiri::HTML(response.body)
      field = document.at_css("input[name='applicant_user[password_confirmation]']")
      message = document.at_css("p.form-error[data-form-validation-error]")
      expect(field["aria-invalid"]).to eq("true")
      expect(message).to be_present
      expect(field["aria-describedby"]).to eq(message["id"])
      expect(field["class"]).to include("kyn-input")
      expect(card_html.scan(legacy_classes)).to be_empty
    end

    it "shows an invalid reset link as an announced alert, not an admin error box" do
      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: "bogus", password: "new-password-1", password_confirmation: "new-password-1" }
      }

      alert = Nokogiri::HTML(response.body).at_css(".kyn-card [role=alert]")
      expect(alert).to be_present
      expect(alert.text).to match(/invalid/i)
      expect(card_html.scan(legacy_classes)).to be_empty
    end
  end

  describe "register from an invitation" do
    let(:token_pair) do
      ApplicantInvitation.issue!(applicant: create(:applicant), email: "invited@example.com", invited_by: create(:user, :psp_admin))
    end
    let(:token) { token_pair.second }

    describe "the form" do
      subject(:subject_page) { get new_applicant_user_registration_path(invitation_token: token) }

      it_behaves_like "a Kynetic auth page"

      it "keeps the invited email read-only and shows the password field with the shared toggle" do
        subject_page

        document = Nokogiri::HTML(response.body)
        email = document.at_css("input[name='applicant_user[email]']")
        expect(email.attribute("readonly")).to be_present
        expect(email["class"]).to include("kyn-input")
        expect(document.css("button[data-action='password-toggle#toggle'][aria-pressed='false']").size).to eq(1)
      end
    end

    it "renders server-side errors as invalid, described fields" do
      post applicant_user_registration_path, params: {
        invitation_token: token,
        applicant_user: {
          first_name: "", last_name: "Applicant", email: "invited@example.com",
          password: "password123!", password_confirmation: "does-not-match"
        }
      }

      document = Nokogiri::HTML(response.body)
      %w[first_name password_confirmation].each do |attribute|
        field = document.at_css("input[name='applicant_user[#{attribute}]']")
        message = field.ancestors("[data-field]").first.at_css("p.form-error[data-form-validation-error]")
        expect(field["aria-invalid"]).to eq("true"), "#{attribute} is not marked invalid"
        expect(message).to be_present, "#{attribute} has no message"
        expect(field["aria-describedby"]).to eq(message["id"])
        expect(field["class"]).not_to include("form-input-error")
      end
      expect(card_html.scan(legacy_classes)).to be_empty
    end
  end

  describe "flash banners" do
    it "announces an error and keeps it on screen" do
      post applicant_user_session_path, params: { applicant_user: { email: "nobody@example.com", password: "wrong" } }

      banner = Nokogiri::HTML(response.body).at_css("[data-testid='flash-alert']")
      expect(banner["role"]).to eq("alert")
      expect(banner["data-toast-dismiss-after-value"]).to eq("0")
      expect(banner["class"]).to include("kyn-")
      expect(banner.to_html.scan(legacy_classes)).to be_empty
    end

    it "keeps a success notice polite and auto-dismissing" do
      user = create(:applicant_user)
      sign_in user, scope: :applicant_user

      delete destroy_applicant_user_session_path
      follow_redirect!

      banner = Nokogiri::HTML(response.body).at_css("[data-testid='flash-notice']")
      expect(banner["role"]).to eq("status")
      expect(banner["data-toast-dismiss-after-value"]).to eq("5000")
      expect(banner.to_html.scan(legacy_classes)).to be_empty
    end

    it "leaves the admin flash partial untouched" do
      expect(Rails.root.join("app/views/layouts/_flash.html.erb").read).to include("data-toast-dismiss-after-value=\"5000\"")
    end
  end
end
