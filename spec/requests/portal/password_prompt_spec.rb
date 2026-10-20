# frozen_string_literal: true

require "rails_helper"

# MH-408: the optional "set a password" prompt on the dashboard, and setting a
# password by email. Names and addresses here are synthetic.
RSpec.describe "Optional password", type: :request do
  let(:user) { create(:applicant_user, :nameless, email: "applicant@example.com") }
  let!(:application) do
    create(:onboarding_application, applicant: user.applicant, current_step: "fulfilment", completed_steps: [ "company" ])
  end

  before do
    ActionMailer::Base.deliveries.clear
    allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456")
    allow(MinimumDuration).to receive(:pause)
    Portal::PasswordSetupsController.portal_rate_limit_store.clear
  end

  def page
    Capybara.string(response.body)
  end

  def reset_token_for(applicant_user)
    applicant_user.send_reset_password_instructions
  end

  describe "the banner on the dashboard" do
    before { sign_in user, scope: :applicant_user }

    it "invites a user with no password who has started, with Set a password and Not now" do
      get portal_root_path

      banner = page.find("#password-prompt")
      expect(banner).to have_text("Sign in faster next time")
      expect(banner).to have_text("Set a password so you don't need an email code each time. It's optional.")
      expect(banner).to have_button("Set a password")
      expect(banner).to have_button("Not now")
    end

    it "is not shown before any step is completed" do
      application.update!(completed_steps: [], current_step: "company")

      get portal_root_path

      expect(page).to have_no_css("#password-prompt")
    end

    it "is not shown to a user who already has a password" do
      sign_in create(:applicant_user, applicant: user.applicant, email: "has.password@example.com"), scope: :applicant_user

      get portal_root_path

      expect(page).to have_no_css("#password-prompt")
    end

    it "is not shown once dismissed" do
      user.touch(:password_prompt_dismissed_at)

      get portal_root_path

      expect(page).to have_no_css("#password-prompt")
    end

    it "never appears on the form or the chat" do
      [ portal_application_path, portal_onboarding_path ].each do |path|
        get path

        expect(response.body).not_to include("Sign in faster next time")
      end
    end

    it "never blocks anything: every page works for a user who ignores it" do
      [ portal_root_path, portal_application_path, portal_onboarding_path ].each do |path|
        get path

        expect(response).to have_http_status(:ok).or have_http_status(:found)
        expect(response).not_to redirect_to(%r{password})
      end
    end
  end

  describe "the permanent link" do
    before { sign_in user, scope: :applicant_user }

    it "reads Set a password for a user with no password, and shows it even after dismissal" do
      user.touch(:password_prompt_dismissed_at)

      get portal_root_path

      expect(page).to have_no_css("#password-prompt")
      expect(page.find("#password-link")).to have_button("Set a password")
    end

    it "reads Change password once one is set" do
      with_password = create(:applicant_user, email: "has.password@example.com")
      sign_in with_password, scope: :applicant_user

      get portal_root_path

      expect(page.find("#password-link")).to have_button("Change password")
    end
  end

  describe "POST /portal/password_dismissal (Not now)" do
    before { sign_in user, scope: :applicant_user }

    it "remembers it, removes the banner by Turbo, and keeps it gone" do
      post portal_password_prompt_dismissal_path, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<turbo-stream action="remove" target="password-prompt">')
      expect(user.reload.password_prompt_dismissed_at).to be_present
      get portal_root_path
      expect(page).to have_no_css("#password-prompt")
    end

    it "goes back to the dashboard without Turbo" do
      post portal_password_prompt_dismissal_path

      expect(response).to redirect_to(portal_root_path)
      expect(user.reload.password_prompt_dismissed_at).to be_present
    end

    it "only ever changes the signed-in user" do
      colleague = create(:applicant_user, :nameless, applicant: user.applicant, email: "colleague@example.com")

      post portal_password_prompt_dismissal_path, params: { id: colleague.id, email: colleague.email }

      expect(colleague.reload.password_prompt_dismissed_at).to be_nil
    end

    it "needs a signed-in applicant" do
      sign_out :applicant_user

      post portal_password_prompt_dismissal_path

      expect(response).to redirect_to(new_applicant_user_session_path)
    end
  end

  describe "POST /portal/password_setup (Set a password)" do
    before { sign_in user, scope: :applicant_user }

    it "emails the reset link to the signed-in user's own address and shows Check your email" do
      post portal_password_setup_path

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(portal_root_path)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "applicant@example.com" ])

      follow_redirect!
      confirmation = page.find("#password-prompt")
      expect(confirmation).to have_text("Check your email")
      expect(confirmation).to have_text("We've sent a link to applicant@example.com to set your password. It works for #{Devise.reset_password_within / 1.hour} hours.")
      expect(confirmation).to have_no_button("Not now")
    end

    it "shows the confirmation once, and the banner is back (not both) on the next visit" do
      post portal_password_setup_path
      follow_redirect!
      expect(page).to have_text("Check your email")
      expect(page).to have_css("#password-prompt", count: 1)

      get portal_root_path

      expect(page).to have_no_text("Check your email")
      expect(page.find("#password-prompt")).to have_text("Sign in faster next time")
    end

    it "shows the confirmation for Change password too, from the permanent link" do
      with_password = create(:applicant_user, email: "has.password@example.com")
      sign_in with_password, scope: :applicant_user

      post portal_password_setup_path
      follow_redirect!

      expect(page.find("#password-prompt")).to have_text("We've sent a link to has.password@example.com")
    end

    it "ignores any address sent with the request" do
      post portal_password_setup_path, params: { email: "attacker@example.com", applicant_user: { email: "attacker@example.com" } }

      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "applicant@example.com" ] ])
    end

    it "is limited to three a hour per user, sending nothing more and saying so kindly" do
      3.times { post portal_password_setup_path }
      expect(ActionMailer::Base.deliveries.size).to eq(3)

      post portal_password_setup_path

      expect(ActionMailer::Base.deliveries.size).to eq(3)
      expect(response).to redirect_to(portal_root_path)
      expect(flash[:alert]).to be_present
    end

    it "needs a signed-in applicant, and sends nothing without one" do
      sign_out :applicant_user

      post portal_password_setup_path, params: { email: user.email }

      expect(response).to redirect_to(new_applicant_user_session_path)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "the emailed link" do
    let(:token) { reset_token_for(user) }

    it "opens for a signed-in user, who sets a password and is signed in afterwards" do
      sign_in user, scope: :applicant_user

      get edit_applicant_user_password_path(reset_password_token: token)
      expect(response).to have_http_status(:ok)

      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      }

      expect(response).to have_http_status(:see_other)
      expect(user.reload.valid_password?("a-new-password-1")).to be(true)
      get portal_root_path
      expect(response).to have_http_status(:ok)
    end

    it "words the page for a user with no password as optional, with a Not now link back to the dashboard" do
      sign_in user, scope: :applicant_user

      get edit_applicant_user_password_path(reset_password_token: token)

      expect(page).to have_css("h1", text: "Set a password")
      expect(page).to have_text("Optional. You can always sign in with an email code instead.")
      expect(page).to have_text("Use at least 8 characters. A short phrase works well.")
      expect(page).to have_button("Save password")
      expect(page.find_link("Not now")[:href]).to eq(portal_root_path)
      expect(page).to have_css("header", count: 1)
    end

    it "keeps the usual wording for someone signed out, or who already has a password" do
      with_password = create(:applicant_user, email: "has.password@example.com")

      get edit_applicant_user_password_path(reset_password_token: reset_token_for(with_password))

      expect(page).to have_css("h1", text: "Set new password")
      expect(page).to have_no_text("Optional. You can always sign in")
      expect(page).to have_no_link("Not now")
    end

    it "still turns signed-in users away from asking for a reset by the old route" do
      sign_in user, scope: :applicant_user

      get new_applicant_user_password_path
      expect(response).to have_http_status(:found)

      post applicant_user_password_path, params: { applicant_user: { email: user.email } }
      expect(response).to have_http_status(:found)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuses a short password, keeping the page and the wording" do
      sign_in user, scope: :applicant_user

      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: token, password: "abcdefg", password_confirmation: "abcdefg" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(page).to have_css("h1", text: "Set a password")
      expect(user.reload.password_set?).to be(false)
    end

    it "refuses a mismatch" do
      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: token, password: "a-new-password-1", password_confirmation: "different-1234" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.password_set?).to be(false)
    end
  end

  describe "the password-changed email" do
    def set_password_through_the_link(applicant_user, password: "a-new-password-1")
      token = reset_token_for(applicant_user)
      ActionMailer::Base.deliveries.clear
      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: token, password: password, password_confirmation: password }
      }
    end

    it "tells an applicant their password was set or changed, and what to do if it wasn't them" do
      set_password_through_the_link(user)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "applicant@example.com" ])
      expect(mail.subject).to eq("Your Kynetic password was changed")
      bodies = [ mail.html_part&.body&.to_s, mail.text_part&.body&.to_s ].compact
      expect(bodies).not_to be_empty
      expect(bodies).to all(match(/password was (set|changed)/i))
      expect(bodies).to all(match(/wasn(?:'|&#39;)t you/i))
      expect(bodies.join).not_to include("a-new-password-1")
    end

    it "is sent for a change as well as a first password" do
      with_password = create(:applicant_user, email: "has.password@example.com")

      set_password_through_the_link(with_password, password: "another-password-2")

      expect(ActionMailer::Base.deliveries.last.subject).to eq("Your Kynetic password was changed")
    end

    it "is not sent for admin users" do
      admin = create(:user, :psp_admin)
      ActionMailer::Base.deliveries.clear

      admin.update!(password: "newpass123", password_confirmation: "newpass123")

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "signing in once a password is set" do
    before do
      token = reset_token_for(user)
      put applicant_user_password_path, params: {
        applicant_user: { reset_password_token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      }
      delete destroy_applicant_user_session_path
    end

    it "works with the password" do
      post applicant_user_session_path, params: { applicant_user: { email: "applicant@example.com", password: "a-new-password-1" } }

      expect(response).to redirect_to(portal_root_path)
    end

    it "fails neutrally with a wrong one, like an unknown address" do
      post applicant_user_session_path, params: { applicant_user: { email: "applicant@example.com", password: "wrong-password" } }
      known = [ response.status, Nokogiri::HTML(response.body).css(".kyn-field, [role='alert'], .flash").text.squish ]

      post applicant_user_session_path, params: { applicant_user: { email: "nobody@example.com", password: "wrong-password" } }

      expect([ response.status, Nokogiri::HTML(response.body).css(".kyn-field, [role='alert'], .flash").text.squish ]).to eq(known)
    end

    it "still lets them sign in with a code" do
      post portal_sign_in_start_path, params: { email: "applicant@example.com" }
      post portal_sign_in_code_path, params: { code: "123456" }

      expect(response).to redirect_to(portal_root_path)
    end
  end
end
