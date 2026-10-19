# frozen_string_literal: true

require "rails_helper"

# MH-406: a returning applicant signs in with a code emailed to them. Whether an
# address has an account must not be learnable from any of it, so most of these
# specs run the same visitor script for a known and an unknown address and
# compare what the visitor can see.
RSpec.describe "Returning applicant sign-in", type: :request do
  let(:applicant) { create(:applicant) }
  let!(:user) { create(:applicant_user, applicant: applicant, email: "returning@example.com") }
  let(:unknown_email) { "unknownxx@example.com" }

  before do
    allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456")
    allow(MinimumDuration).to receive(:pause)
  end

  def start_with(email)
    post portal_sign_in_start_path, params: { email: email }
  end

  def verify(code = "123456")
    post portal_sign_in_code_path, params: { code: code }
  end

  def page
    Capybara.string(response.body)
  end

  def text
    page.text.squish
  end

  # What the visitor can see of the last response: no tokens that change on
  # every request, and the address blanked out.
  def snapshot(email)
    document = Nokogiri::HTML(response.body)
    document.css("meta[name='csrf-token'], meta[name='csrf-param'], meta[name='csp-nonce'], input[name='authenticity_token']").remove
    document.css("[nonce]").each { |node| node.remove_attribute("nonce") }
    cookie = response.headers["Set-Cookie"].to_s
    {
      status: response.status,
      location: response.location,
      cache_control: response.headers["Cache-Control"],
      robots: response.headers["X-Robots-Tag"],
      session_shape: session.to_h.except("session_id").to_json.gsub(/[0-9a-f]{8}-[0-9a-f-]{27}/, "UUID").gsub(email, "EMAIL").gsub(/"decoy":[01]/, "\"decoy\":X"),
      cookie_sent: cookie.present?,
      cookie_length: cookie.length,
      flash: flash.to_h,
      body: document.to_html.gsub(email, "EMAIL")
    }
  end

  # A new visitor: no cookies, and nothing counted against them yet.
  def new_visitor
    reset!
    Portal::SignInCodesController.portal_rate_limit_store.clear
  end

  def visitor_script(email)
    new_visitor
    t0 = Time.zone.parse("2026-10-19 12:00:00")
    steps = []
    travel_to(t0) do
      start_with(email)
      steps << snapshot(email)
      get portal_sign_in_code_path
      steps << snapshot(email)
      2.times do
        verify("000000")
        steps << snapshot(email)
      end
      post portal_sign_in_code_resend_path
      steps << snapshot(email)
    end
    travel_to(t0 + 40.seconds) do
      post portal_sign_in_code_resend_path
      steps << snapshot(email)
      5.times do
        verify("000000")
        steps << snapshot(email)
      end
      get portal_sign_in_code_path
      steps << snapshot(email)
    end
    travel_to(t0 + 15.minutes) do
      get portal_sign_in_code_path
      steps << snapshot(email)
    end
    steps
  end

  describe "the pages" do
    it "makes /portal/sign_in the Welcome back page, never cached or indexed" do
      get new_applicant_user_session_path

      expect(response).to have_http_status(:ok)
      expect(text).to include("Welcome back")
      expect(text).to include("Enter your email and we'll send you a code to sign in.")
      field = page.find_field("email")
      expect([ field[:type], field[:required], field[:autofocus], field[:autocomplete] ]).to eq([ "email", "required", "autofocus", "username email" ])
      expect(page.find("button, input[type='submit']", text: "Send me a code")).to be_present
      expect(page.find_link("Use a password instead")[:href]).to eq(applicant_user_password_sign_in_path)
      expect(text).to include("Invited for the first time? Use the link in your invitation email.")
      expect(page).to have_no_field("applicant_user[password]")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["X-Robots-Tag"]).to include("noindex")
    end

    it "serves the password form at /portal/sign_in/password, still posting to Devise" do
      get applicant_user_password_sign_in_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_field("applicant_user[email]")
      expect(page).to have_field("applicant_user[password]", type: "password")
      expect(page.find("form[action='#{applicant_user_session_path}']")["method"]).to eq("post")
      expect(page.find_link("Email me a code instead")[:href]).to eq(new_applicant_user_session_path)
    end

    it "keeps showing the password form after a failed password sign-in" do
      post applicant_user_session_path, params: { applicant_user: { email: user.email, password: "wrong-password" } }

      expect(page).to have_field("applicant_user[password]", type: "password")
      expect(text).not_to include("Send me a code")
      expect(page).to have_field("applicant_user[email]", with: user.email)
    end

    it "still signs in with a password" do
      post applicant_user_session_path, params: { applicant_user: { email: user.email, password: "password123!" } }

      expect(response).to redirect_to(portal_root_path)
    end

    it "sends a signed-in user on, from either page" do
      sign_in user, scope: :applicant_user

      get new_applicant_user_session_path
      expect(response).to have_http_status(:found)

      get applicant_user_password_sign_in_path
      expect(response).to have_http_status(:found)
    end
  end

  describe "asking for a code" do
    it "sends a code to a known address and goes to the enter-code page" do
      expect { start_with(user.email) }.to change(ApplicantSignInCode, :count).by(1).and have_enqueued_job(ActionMailer::MailDeliveryJob).once

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(portal_sign_in_code_path)
      expect(ApplicantSignInCode.last).to have_attributes(email: user.email, applicant_id: applicant.id, applicant_invitation_id: nil)
    end

    it "stores, sends and creates nothing for an unknown address" do
      expect { start_with(unknown_email) }.not_to(change { [ ApplicantSignInCode.count, ApplicantUser.count, ApplicantInvitation.count ] })

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      expect(response).to redirect_to(portal_sign_in_code_path)
    end

    it "finds the account whatever the case or spacing of the address" do
      expect { start_with("  Returning@Example.COM ") }.to change(ApplicantSignInCode, :count).by(1)
    end

    it "gives a known and an unknown address exactly the same answer, to the byte, apart from the address" do
      known = visitor_script(user.email)
      unknown = visitor_script(unknown_email)

      known.zip(unknown).each_with_index do |(a, b), index|
        expect(a.except(:cookie_length)).to eq(b.except(:cookie_length)), "step #{index + 1} differs:\n known: #{a.except(:body)}\n unknown: #{b.except(:body)}"
        # The cookie is compressed, so equal contents still vary a few bytes with the random ids inside.
        expect(a[:cookie_length]).to be_within(48).of(b[:cookie_length]), "step #{index + 1}: the cookies differ in size (#{a[:cookie_length]} vs #{b[:cookie_length]})"
      end
    end

    it "words the enter-code page for a returning applicant as a maybe, for known and unknown alike" do
      [ user.email, unknown_email ].each do |address|
        reset!
        start_with(address)
        get portal_sign_in_code_path

        expect(text).to include("If that address is registered, we've sent a 6-digit code to #{address}. It expires in 10 minutes.")
      end
    end

    it "shows a fixed thirty seconds when a request lands inside the real gap, for known and unknown alike" do
      [ user.email, unknown_email ].each do |address|
        reset!
        travel_to(Time.zone.parse("2026-10-19 12:00:00")) { start_with(address) }
        travel_to(Time.zone.parse("2026-10-19 12:00:10")) do
          start_with(address)
          get portal_sign_in_code_path
        end

        expect(page.find("[data-controller~='resend-countdown']")["data-resend-countdown-seconds-value"]).to eq("30")
      end
    end

    it "confirms an unconfirmed account once the code is right, and works for an account with no password" do
      nameless = create(:applicant_user, :nameless, :unconfirmed, email: "nameless@example.com")

      start_with(nameless.email)
      verify

      expect(response).to redirect_to(portal_root_path)
      expect(nameless.reload).to be_confirmed
      get portal_root_path
      expect(response).to have_http_status(:ok)
    end

    it "signs in a known address with the right code, with a new session" do
      start_with(user.email)
      before_id = session.id.to_s

      verify

      expect(response).to redirect_to(portal_root_path)
      expect(session.id.to_s).not_to eq(before_id)
      get portal_root_path
      expect(response).to have_http_status(:ok)
    end

    it "never signs an unknown address in, whatever code is typed" do
      start_with(unknown_email)

      [ "123456", "000000", "654321" ].each { |code| verify(code) }

      get portal_root_path
      expect(response).to redirect_to(new_applicant_user_session_path)
      expect(ApplicantUser.where(email: unknown_email)).to be_empty
    end

    it "asks for a valid address, saying nothing about accounts" do
      [ "", "not an address", "a" * 300 + "@example.com" ].each do |bad|
        start_with(bad)

        expect(response).to have_http_status(:unprocessable_content)
        expect(page).to have_css(".kyn-field [data-form-validation-error], [role='alert']", text: "Enter a valid email address")
        expect(page).to have_field("email")
      end
      expect(ApplicantSignInCode.count).to eq(0)
    end

    it "pads every answer to the same minimum time, known or not" do
      start_with(user.email)
      start_with(unknown_email)

      expect(MinimumDuration).to have_received(:pause).twice
    end

    it "never puts the address or the code in the request log" do
      output = StringIO.new
      logger = ActiveSupport::Logger.new(output)
      Rails.logger.broadcast_to(logger)

      start_with(user.email)
      verify("123456")

      Rails.logger.stop_broadcasting_to(logger)
      expect(output.string).not_to include("123456")
      expect(output.string).not_to include("returning%40example.com")
      expect(output.string).not_to match(/Parameters:.*returning@example\.com/)
    end

    it "logs that a code was asked for, with a fingerprint of the address and whether it had an account" do
      allow(SecurityEventLogger).to receive(:log_event).and_call_original
      allow(SecurityEventLogger).to receive(:log_event).with(hash_including(event: "portal.sign_in.start"))

      start_with(user.email)
      start_with(unknown_email)

      expect(SecurityEventLogger).to have_received(:log_event).with(
        event: "portal.sign_in.start", email_fingerprint: SecurityEventLogger.fingerprint(user.email), account_found: true
      )
      expect(SecurityEventLogger).to have_received(:log_event).with(
        event: "portal.sign_in.start", email_fingerprint: SecurityEventLogger.fingerprint(unknown_email), account_found: false
      )
    end
  end

  describe "the limits" do
    it "stops any address at ten requests an hour, with the same page for a known and an unknown one" do
      pages = [ user.email, unknown_email ].map do |address|
        new_visitor
        t0 = Time.zone.parse("2026-10-19 12:00:00")
        10.times do |i|
          travel_to(t0 + (i * 3).minutes) { start_with(address) }
          expect(response).to have_http_status(:see_other)
        end
        travel_to(t0 + 30.minutes) { start_with(address) }
        expect(response).to have_http_status(:too_many_requests)
        [ response.status, Nokogiri::HTML(response.body).css("body").text.squish, response.headers["Cache-Control"] ]
      end

      expect(pages.first).to eq(pages.last)
      expect(pages.first[1]).to include("Try again later")
    end

    it "counts the address by a keyed fingerprint, never the address itself" do
      start_with(user.email)

      keys = Portal::SignInCodesController.portal_rate_limit_store.instance_variable_get(:@data).keys.join(" ")
      expect(keys).not_to include(user.email)
    end

    it "stops one connection at five requests in ten minutes, whichever addresses it asks about" do
      5.times { |i| start_with("person#{i}@example.com") }
      expect(response).to have_http_status(:see_other)

      start_with(user.email)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "keeps requests for bad addresses out of any shared allowance" do
      4.times { start_with("") }

      start_with(user.email)

      expect(response).to have_http_status(:see_other)
      keys = Portal::SignInCodesController.portal_rate_limit_store.instance_variable_get(:@data).keys
      expect(keys.grep(/address/).join(" ")).not_to match(/address:\z|address: /)
    end

    it "stops resends of a returning applicant, known or not, at ten codes an hour" do
      results = [ user.email, unknown_email ].map do |address|
        new_visitor
        t0 = Time.zone.parse("2026-10-19 12:00:00")
        travel_to(t0) { start_with(address) }
        statuses = (1..10).map do |i|
          travel_to(t0 + (i * 2.6).minutes) { post portal_sign_in_code_resend_path }
          response.status
        end
        statuses
      end

      expect(results.first).to eq(results.last)
      expect(results.first.last).to eq(429)
      expect(results.first.first(9).uniq).to eq([ 303 ])
    end
  end
end
