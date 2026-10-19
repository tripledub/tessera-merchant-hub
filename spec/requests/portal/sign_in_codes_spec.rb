# frozen_string_literal: true

require "rails_helper"

# MH-405: the one-time-code sign-in screens for an invited applicant. The code
# service itself (MH-404) has its own specs; these cover the flow around it.
RSpec.describe "Portal sign-in codes", type: :request do
  let(:applicant) { create(:applicant, name: "Acme Widgets Ltd") }
  let(:inviter) { create(:user, :psp_admin, email: "psp.admin@example.com") }
  let(:email) { "invited@example.com" }
  let(:issued) { ApplicantInvitation.issue!(applicant: applicant, email: email, invited_by: inviter) }
  let(:invitation) { issued.first }
  let(:token) { issued.second }

  before { allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456") }

  def start(for_token = token)
    post portal_invitation_code_path(for_token)
  end

  def verify(code = "123456", **extra)
    post portal_sign_in_code_path, params: { code: code }.merge(extra)
  end

  def text
    Nokogiri::HTML(response.body).text.squish
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def codes
    ApplicantSignInCode.where(applicant_id: applicant.id)
  end

  def expect_private_page
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["X-Robots-Tag"]).to include("noindex")
  end

  describe "POST /portal/invitations/:token/code (Continue)" do
    it "sends a code to the invited address and goes to the enter-code page" do
      expect { start }.to change(codes, :count).by(1)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(portal_sign_in_code_path)
      expect(codes.last).to have_attributes(email: email, applicant_invitation_id: invitation.id)
    end

    it "emails the code in the background" do
      token

      expect { start }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "keeps the pending state in the session, never in the URL, and the address out of the cookie in plain text" do
      start

      expect(response.location).not_to include(email)
      expect(response.headers["Set-Cookie"]).not_to include(email)
      expect(session[:portal_pending_sign_in]).to include(
        "applicant_id" => applicant.id, "invitation_id" => invitation.id, "email" => email, "invitation_token" => token
      )
    end

    it "is never cached or indexed" do
      start

      expect_private_page
    end

    it "shows the dead-link page for an unknown, expired, claimed or revoked invitation, and sends nothing" do
      expired, expired_token = ApplicantInvitation.issue!(applicant: applicant, email: "a@example.com", invited_by: inviter)
      expired.update!(expires_at: 1.minute.ago)
      revoked, revoked_token = ApplicantInvitation.issue!(applicant: applicant, email: "b@example.com", invited_by: inviter)
      revoked.update!(revoked_at: Time.current)

      expect do
        [ "unknown-token", expired_token, revoked_token ].each do |dead|
          start(dead)

          expect(response).to have_http_status(:not_found)
          expect(text).to include("This link has expired")
        end
      end.not_to change(ApplicantSignInCode, :count)
    end

    it "carries on to the enter-code page when a code was only just sent (a double click)" do
      start
      expect { start }.not_to change(ApplicantSignInCode, :count)

      expect(response).to redirect_to(portal_sign_in_code_path)
    end

    it "shows the try again later page when this address has asked for too many codes" do
      create_list(:applicant_sign_in_code, ApplicantSignInCodes::Issue::HOURLY_CAP,
                  applicant: applicant, email: email, created_at: 5.minutes.ago)

      start

      expect(response).to have_http_status(:too_many_requests)
      expect(text).to include("Try again later")
      expect(page.css("form button, form input[type='submit']")).to be_empty
      expect_private_page
    end

    it "is limited to five code requests per ten minutes per address" do
      5.times { start }
      expect(response).to have_http_status(:see_other)

      start

      expect(response).to have_http_status(:too_many_requests)
      expect(text).to include("Try again later")
    end
  end

  describe "GET /portal/sign_in/code" do
    it "sends someone with no pending sign-in to the sign-in page" do
      get portal_sign_in_code_path

      expect(response).to redirect_to(new_applicant_user_session_path)
      expect(flash[:alert]).to be_present
    end

    it "sends someone whose pending sign-in is older than thirty minutes to the sign-in page" do
      start

      travel_to(31.minutes.from_now) { get portal_sign_in_code_path }

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    context "with a fresh code" do
      before do
        start
        get portal_sign_in_code_path
      end

      it "shows the address in full, six labelled boxes in one group, and a disabled Verify button" do
        expect(response).to have_http_status(:ok)
        expect(text).to include("Check your email")
        expect(text).to include(email)
        expect(text).to include("It expires in 10 minutes")

        expect(page.css("fieldset legend").map { |legend| legend.text.strip }).to include("One-time verification code")
        boxes = page.css("fieldset input[data-code-input-target='box']")
        expect(boxes.size).to eq(6)
        expect(boxes.map { |box| box["aria-label"] }).to eq((1..6).map { |n| "Digit #{n} of 6" })
        expect(boxes.map { |box| box["inputmode"] }.uniq).to eq([ "numeric" ])
        expect(boxes.first["autocomplete"]).to eq("one-time-code")
        expect(boxes.drop(1).map { |box| box["autocomplete"] }.uniq).to eq([ "off" ])
        expect(boxes.map { |box| box["maxlength"] }.compact).to be_empty

        verify_button = page.at_css("form button[type='submit'], form input[type='submit']")
        expect(verify_button.text.strip.presence || verify_button["value"]).to eq("Verify and continue")
        expect(verify_button["disabled"]).to be_present
      end

      it "submits only the assembled code, never the individual boxes" do
        form = page.at_css("form[action='#{portal_sign_in_code_path}']")

        expect(form["method"]).to eq("post")
        expect(form.css("input[name='code']").size).to eq(1)
        expect(page.css("fieldset input[name]")).to be_empty
      end

      it "tells the page how long until another code may be sent" do
        countdown = page.at_css("[data-controller~='resend-countdown']")

        expect(countdown["data-resend-countdown-seconds-value"].to_i).to be_between(25, 30)
        expect(page.at_css("form[action='#{portal_sign_in_code_resend_path}']")).to be_present
      end

      it "links back to the invitation and to the person who invited the applicant, without naming them" do
        expect(page.css("a").find { |link| link.text.strip.include?("Back") }["href"]).to eq(portal_invitation_path(token))
        expect(text).to include("Wrong email? Contact the person who invited you.")
        expect(response.body).not_to include(inviter.email)
      end

      it "is never cached or indexed" do
        expect_private_page
      end

      it "never contains the code" do
        expect(response.body).not_to include("123456")
      end
    end

    it "takes the address from the session only, whatever the request says" do
      start

      get portal_sign_in_code_path(email: "attacker@example.com", applicant_id: 0, token: "x")

      expect(text).to include(email)
      expect(response.body).not_to include("attacker@example.com")
    end

    it "shows the expired page once the code has expired, and offers a new one" do
      start

      travel_to(11.minutes.from_now) { get portal_sign_in_code_path }

      expect(text).to include("This code has expired")
      expect(text).to include(email)
      expect(page.at_css("form[action='#{portal_sign_in_code_resend_path}']")).to be_present
      expect(text).to include("Send a new code")
    end

    it "shows the expired page for a code that was already used" do
      start
      codes.last.update!(consumed_at: Time.current)

      get portal_sign_in_code_path

      expect(text).to include("This code has expired")
    end

    it "shows the expired page when there is no code at all" do
      start
      codes.delete_all

      get portal_sign_in_code_path

      expect(text).to include("This code has expired")
    end

    it "shows the too-many-attempts page for a locked code" do
      start
      codes.last.update!(attempts: ApplicantSignInCode::MAX_ATTEMPTS)

      get portal_sign_in_code_path

      expect(text).to include("Too many attempts")
      expect(text).to include("Send a new code")
    end
  end

  describe "POST /portal/sign_in/code (verify)" do
    before { start }

    it "needs a pending sign-in" do
      reset!

      verify

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    context "with the right code" do
      it "creates a confirmed user with no name and no password, and claims the invitation" do
        expect { verify }.to change(ApplicantUser, :count).by(1)

        user = ApplicantUser.find_by!(email: email)
        expect(user).to have_attributes(applicant_id: applicant.id, first_name: nil, last_name: nil)
        expect(user).to be_confirmed
        expect(user.encrypted_password).to be_blank
        expect(invitation.reload).to have_attributes(claimed_by_id: user.id, claimed_at: be_present)
      end

      it "sends no confirmation email" do
        expect { perform_enqueued_jobs { verify } }.not_to(change { ActionMailer::Base.deliveries.count })
      end

      it "signs the applicant in and goes to the dashboard" do
        verify

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(portal_root_path)

        get portal_root_path
        expect(response).to have_http_status(:ok)
      end

      it "starts a new session and clears the pending state" do
        before_id = session.id.to_s

        verify

        expect(session.id.to_s).not_to eq(before_id)
        expect(session[:portal_pending_sign_in]).to be_nil
        get portal_sign_in_code_path
        expect(response).to redirect_to(new_applicant_user_session_path).or redirect_to(portal_root_path)
      end

      it "signs in an existing user without creating another, and confirms them" do
        user = create(:applicant_user, :unconfirmed, applicant: applicant, email: email)

        expect { verify }.not_to change(ApplicantUser, :count)

        expect(user.reload).to be_confirmed
        expect(response).to redirect_to(portal_root_path)
      end

      it "leaves an existing user's name and password alone" do
        user = create(:applicant_user, applicant: applicant, email: email, first_name: "Sam")

        expect { verify }.not_to(change { user.reload.slice(:first_name, :encrypted_password) })
      end

      it "uses the code once" do
        verify
        get portal_sign_in_code_path
        expect(codes.last).to be_consumed
      end
    end

    context "with a wrong code" do
      it "shows the enter-code page again with how many attempts are left" do
        verify("000000")

        expect(response).to have_http_status(:unprocessable_content)
        expect(text).to include("That code isn't right. You have 4 attempts left.")
        alert = page.at_css("[role='alert']")
        expect(alert.text).to include("4 attempts left")
        boxes = page.css("input[data-code-input-target='box']")
        expect(boxes.map { |box| box["aria-invalid"] }.uniq).to eq([ "true" ])
        expect(boxes.map { |box| box["value"].to_s }.uniq).to eq([ "" ])
        expect(page.at_css("[data-code-input-error-value='true']")).to be_present
        expect_private_page
      end

      it "says '1 attempt left' in the singular" do
        4.times { verify("000000") }

        expect(text).to include("You have 1 attempt left.")
      end

      it "creates no user and does not sign in" do
        expect { verify("000000") }.not_to change(ApplicantUser, :count)

        get portal_root_path
        expect(response).to redirect_to(new_applicant_user_session_path)
      end

      it "locks the code after five wrong attempts, and the right code no longer works" do
        5.times { verify("000000") }
        expect(response).to redirect_to(portal_sign_in_code_path)

        follow_redirect!
        expect(text).to include("Too many attempts")

        verify("123456")
        follow_redirect!

        expect(text).to include("Too many attempts")
        expect(ApplicantUser.where(email: email)).to be_empty
      end

      it "asks for all six digits, without using an attempt, when the code is missing, short or odd" do
        [ nil, "", "abc", "12", { "a" => "1" }, [ "123456" ] ].each do |odd|
          post portal_sign_in_code_path, params: { code: odd }

          expect(response).to have_http_status(:unprocessable_content)
          expect(text).to include("Enter all 6 digits of the code.")
        end
        expect(codes.last.attempts).to eq(0)
        expect(ApplicantUser.where(email: email)).to be_empty
      end
    end

    it "shows the expired page for an expired code" do
      travel_to(11.minutes.from_now) { verify }

      expect(response).to redirect_to(portal_sign_in_code_path)
      travel_to(11.minutes.from_now) { follow_redirect! }
      expect(text).to include("This code has expired")
      expect(ApplicantUser.where(email: email)).to be_empty
    end

    it "ignores any address or applicant sent with the request" do
      other = create(:applicant)

      verify("123456", email: "attacker@example.com", applicant_id: other.id)

      expect(ApplicantUser.find_by(email: email)).to be_present
      expect(ApplicantUser.find_by(email: "attacker@example.com")).to be_nil
    end

    it "shows the dead-link page, and signs nobody in, when the invitation died mid-flow" do
      invitation.update!(expires_at: 1.minute.ago)

      expect { verify }.not_to change(ApplicantUser, :count)

      expect(response).to have_http_status(:not_found)
      expect(text).to include("This link has expired")
      get portal_root_path
      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "shows the dead-link page when the address already belongs to another company's user" do
      create(:applicant_user, email: email)

      expect { verify }.not_to change(ApplicantUser, :count)

      expect(response).to have_http_status(:not_found)
      expect(text).to include("This link has expired")
      expect(invitation.reload.claimed_at).to be_nil
    end

    it "is limited to ten verifications per ten minutes per address" do
      10.times { verify("000000") }
      expect(response).not_to have_http_status(:too_many_requests)

      verify("000000")

      expect(response).to have_http_status(:too_many_requests)
      expect(text).to include("Try again later")
    end

    it "never puts the code in the request log" do
      output = StringIO.new
      logger = ActiveSupport::Logger.new(output)
      Rails.logger.broadcast_to(logger)

      verify("123456")

      Rails.logger.stop_broadcasting_to(logger)
      expect(output.string).to include("/portal/sign_in/code")
      expect(output.string).not_to include("123456")
    end
  end

  describe "POST /portal/sign_in/code/resend" do
    before { start }

    it "needs a pending sign-in" do
      reset!

      post portal_sign_in_code_resend_path

      expect(response).to redirect_to(new_applicant_user_session_path)
    end

    it "sends a new code once the gap has passed, and goes back to the enter-code page" do
      travel_to(31.seconds.from_now) do
        expect { post portal_sign_in_code_resend_path }.to change(codes, :count).by(1)
      end

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(portal_sign_in_code_path)
    end

    it "sends nothing, and returns to the page with the countdown, when asked too soon" do
      expect { post portal_sign_in_code_resend_path }.not_to change(codes, :count)

      expect(response).to redirect_to(portal_sign_in_code_path)
      follow_redirect!
      expect(page.at_css("[data-controller~='resend-countdown']")["data-resend-countdown-seconds-value"].to_i).to be_between(1, 30)
    end

    it "offers a new code from the expired page" do
      travel_to(11.minutes.from_now) do
        post portal_sign_in_code_resend_path
        follow_redirect!

        expect(text).to include("Check your email")
        expect(codes.count).to eq(2)
      end
    end

    it "shows the try again later page, with no button, at the address's limit" do
      create_list(:applicant_sign_in_code, ApplicantSignInCodes::Issue::HOURLY_CAP,
                  applicant: applicant, email: email, created_at: 5.minutes.ago)

      travel_to(31.seconds.from_now) { post portal_sign_in_code_resend_path }

      expect(response).to have_http_status(:too_many_requests)
      expect(text).to include("Try again later")
      expect(page.css("form button, form input[type='submit']")).to be_empty
    end

    it "shows the dead-link page, and sends nothing, when the invitation died mid-flow" do
      invitation.update!(revoked_at: Time.current)

      travel_to(31.seconds.from_now) do
        expect { post portal_sign_in_code_resend_path }.not_to change(codes, :count)
      end

      expect(response).to have_http_status(:not_found)
    end

    it "shares the five-per-ten-minutes limit with the first request" do
      4.times { post portal_sign_in_code_resend_path }
      expect(response).to have_http_status(:see_other)

      post portal_sign_in_code_resend_path

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
