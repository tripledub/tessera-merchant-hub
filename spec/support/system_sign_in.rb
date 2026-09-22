# frozen_string_literal: true

# MH-314: Devise::Test::IntegrationHelpers#sign_in (used by request specs) sets
# a Warden test-mode session that a real browser driver never sees — Cuprite
# makes genuine HTTP requests to the app, so system specs sign in through the
# actual form instead.
module SystemSignIn
  def sign_in_via_form(user, password:)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: password
    click_button "Sign in"
  end
end

RSpec.configure do |config|
  config.include SystemSignIn, type: :system
end
