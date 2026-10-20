# frozen_string_literal: true

require "rails_helper"

# MH-403: the invitation landing page, the one friendly page every dead link
# gets (no enumeration), and "Request a new link".
RSpec.describe "Portal invitations", type: :request do
  let(:applicant) { create(:applicant, name: "Acme Widgets Ltd", contact_email: "owner@example.com") }
  let(:inviter) { create(:user, :psp_admin, email: "psp.admin@example.com") }
  let(:invited_email) { "invited@example.com" }
  let(:issued) { ApplicantInvitation.issue!(applicant: applicant, email: invited_email, invited_by: inviter) }
  let(:invitation) { issued.first }
  let(:token) { issued.second }

  # Everything that legitimately differs between two dead-link responses (the
  # token echoed in the form action and the CSRF token) is blanked out.
  def normalised(body, dead_token = nil)
    document = Nokogiri::HTML(body)
    document.css("meta[name='csrf-token'], meta[name='csrf-param']").remove
    document.css("input[name='authenticity_token']").remove
    document.css("form").each { |form| form["action"] = "ACTION" }
    html = document.to_html
    dead_token ? html.gsub(dead_token, "TOKEN") : html
  end

  def expire(invitation)
    invitation.update!(expires_at: 1.minute.ago)
  end

  def claim(invitation)
    user = create(:applicant_user, applicant: invitation.applicant, email: invitation.email)
    invitation.claim!(user)
  end

  describe "GET /portal/invitations/:token with a usable token" do
    before { get portal_invitation_path(token) }

    it "renders the landing page instead of redirecting" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You&#39;ve been invited").or include("You've been invited")
      expect(response.body).to include("Complete your onboarding for Acme Widgets Ltd")
    end

    it "explains what happens next" do
      text = Nokogiri::HTML(response.body).text
      expect(text).to include("It takes about 10 minutes")
      expect(text).to include("pick up where you left off")
      expect(text).to include("Confirm your email with a one-time code")
      expect(text).to include("Answer a few questions about your business")
      expect(text).to include("Upload your documents")
    end

    it "shows the invited address in full, and nothing about the sender" do
      expect(response.body).to include(invited_email)
      expect(response.body).to include("We&#39;ll send a code to this address").or include("We'll send a code to this address")
      expect(response.body).not_to include(inviter.email)
    end

    it "offers a single Continue button that posts to send a code, carrying the token, and no email input" do
      document = Nokogiri::HTML(response.body)

      form = document.css("form").find { |candidate| candidate["action"] == portal_invitation_code_path(token) }
      expect(form["method"]).to eq("post")
      expect(form.at_css("button, input[type='submit']").text.strip).to eq("Continue")
      expect(document.css("button, input[type='submit']").count { |button| button.text.strip == "Continue" }).to eq(1)
      expect(document.css("a").none? { |link| link["href"].to_s.include?("registration") || link.text.strip == "Continue" }).to be(true)
      expect(document.css("input[type='email'], input[name*='email']")).to be_empty
    end

    it "is never cached or indexed" do
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["X-Robots-Tag"]).to include("noindex")
    end

    it "uses the applicant layout" do
      expect(response.body).to include("font-kynetic")
      expect(response.body).not_to include('data-controller="dark-mode"')
    end
  end

  describe "dead links" do
    let(:unknown_token) { "unknown-token" }

    def dead_responses
      responses = {}
      get portal_invitation_path("unknown-token")
      responses[:unknown] = [ response.status, normalised(response.body, "unknown-token") ]

      expired_invitation, expired_token = ApplicantInvitation.issue!(applicant: applicant, email: "a@example.com", invited_by: inviter)
      expire(expired_invitation)
      get portal_invitation_path(expired_token)
      responses[:expired] = [ response.status, normalised(response.body, expired_token) ]

      claimed_invitation, claimed_token = ApplicantInvitation.issue!(applicant: applicant, email: "b@example.com", invited_by: inviter)
      claim(claimed_invitation)
      get portal_invitation_path(claimed_token)
      responses[:claimed] = [ response.status, normalised(response.body, claimed_token) ]

      revoked_invitation, revoked_token = ApplicantInvitation.issue!(applicant: applicant, email: "c@example.com", invited_by: inviter)
      revoked_invitation.update!(revoked_at: Time.current)
      get portal_invitation_path(revoked_token)
      responses[:revoked] = [ response.status, normalised(response.body, revoked_token) ]
      responses
    end

    it "renders the same friendly 404 page whatever the reason" do
      responses = dead_responses

      expect(responses.values.map(&:first).uniq).to eq([ 404 ])
      expect(responses.values.map(&:last).uniq.size).to eq(1)
    end

    it "gives the page its content: expired, request a new link, sign in, contact the inviter" do
      get portal_invitation_path(unknown_token)
      document = Nokogiri::HTML(response.body)

      expect(document.text).to include("This link has expired")
      expect(document.text).to include("Contact the person who invited you")
      expect(document.css("form button, form input[type='submit']").map { |b| b.text.strip.presence || b["value"] }).to include("Request a new link")
      expect(document.at_css("form")["action"]).to eq(portal_invitation_renewal_path(unknown_token))
      # Turbo refuses to render a plain 200 response to a form submission, so this one is a normal request.
      expect(document.at_css("form")["data-turbo"]).to eq("false")
      expect(document.css("a").find { |link| link.text.strip == "Sign in" }["href"]).to eq(new_applicant_user_session_path)
    end

    it "reveals nothing about the invitation, the company or the inviter" do
      expire(invitation)

      get portal_invitation_path(token)

      expect(response.body).not_to include(applicant.name)
      expect(response.body).not_to include(invited_email)
      expect(response.body).not_to include(inviter.email)
    end

    it "is never cached or indexed" do
      get portal_invitation_path(unknown_token)

      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["X-Robots-Tag"]).to include("noindex")
    end

    it "still logs the invalid access" do
      allow(SecurityEventLogger).to receive(:log)

      get portal_invitation_path(unknown_token)

      expect(SecurityEventLogger).to have_received(:log).with(event: "portal.invalid_access", request: anything)
    end

    it "is also what the registration form shows for a dead token (new and create)" do
      get portal_invitation_path(unknown_token)
      landing = [ response.status, normalised(response.body, unknown_token) ]

      get new_applicant_user_registration_path(invitation_token: unknown_token)
      new_page = [ response.status, normalised(response.body, unknown_token) ]

      post applicant_user_registration_path, params: {
        invitation_token: unknown_token,
        applicant_user: { first_name: "Jane", last_name: "Doe", password: "password123!", password_confirmation: "password123!" }
      }
      create_page = [ response.status, normalised(response.body, unknown_token) ]

      expect(new_page).to eq(landing)
      expect(create_page).to eq(landing)
    end

    it "shows the page when a registration loses the race for the invitation" do
      token
      allow(ApplicantUser).to receive(:new).and_wrap_original do |original, *arguments|
        original.call(*arguments).tap { |user| allow(user).to receive(:save).and_raise(ActiveRecord::RecordNotUnique) }
      end

      post applicant_user_registration_path, params: {
        invitation_token: token,
        applicant_user: { first_name: "Jane", last_name: "Doe", password: "password123!", password_confirmation: "password123!" }
      }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("This link has expired")
    end
  end

  describe "POST /portal/invitations/:token/renewal" do
    def confirmation_for(request_token)
      post portal_invitation_renewal_path(request_token)
      [ response.status, normalised(response.body, request_token) ]
    end

    it "sends a fresh link to the invited address for an expired invitation" do
      expire(invitation)

      expect {
        perform_enqueued_jobs { post portal_invitation_renewal_path(token) }
      }.to change(ApplicantInvitation, :count).by(1)

      renewed = ApplicantInvitation.order(:created_at).last
      expect(renewed).to have_attributes(applicant_id: applicant.id, email: invited_email, invited_by_id: inviter.id)
      expect(renewed.expires_at).to be_within(1.minute).of(ApplicantInvitation::EXPIRY.from_now)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ invited_email ])
      new_token = mail.text_part.body.to_s[%r{/portal/invitations/([\w-]+)}, 1]
      expect(ApplicantInvitation.find_usable_by_token(new_token)).to eq(renewed)
    end

    # MH-412: Solid Queue keeps a job's arguments in the queue database, so a
    # one-time link must not be among them in plaintext.
    it "keeps the link and the token out of the background job's arguments, and still delivers a working link" do
      expire(invitation)

      post portal_invitation_renewal_path(token)

      job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |queued| queued["job_class"] == "ActionMailer::MailDeliveryJob" }
      arguments = job["arguments"].to_json
      expect(arguments).not_to include("/portal/invitations/")
      expect(arguments).not_to include("http")

      perform_enqueued_jobs
      mail = ActionMailer::Base.deliveries.last
      new_token = mail.text_part.body.to_s[%r{/portal/invitations/([\w-]+)}, 1]
      expect(new_token).to be_present
      expect(arguments).not_to include(new_token)
      expect(ApplicantInvitation.find_usable_by_token(new_token)).to be_present
    end

    it "delivers in the background" do
      expire(invitation)

      expect { post portal_invitation_renewal_path(token) }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "shows a neutral confirmation" do
      expire(invitation)

      post portal_invitation_renewal_path(token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Check your email")
      expect(response.body).to include("If your invitation can be renewed")
      expect(response.body).not_to include(invited_email)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "sends nothing for an unknown, claimed, revoked or not-yet-expired invitation" do
      claimed, claimed_token = ApplicantInvitation.issue!(applicant: applicant, email: "b@example.com", invited_by: inviter)
      expire(claimed)
      claim(claimed)
      revoked, revoked_token = ApplicantInvitation.issue!(applicant: applicant, email: "c@example.com", invited_by: inviter)
      expire(revoked)
      revoked.update!(revoked_at: Time.current)
      live_token = token

      expect {
        perform_enqueued_jobs do
          [ "unknown-token", claimed_token, revoked_token, live_token ].each { |t| post portal_invitation_renewal_path(t) }
        end
      }.not_to change(ApplicantInvitation, :count)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "gives the same response in every case, so nothing can be learned from it" do
      expire(invitation)
      acted = confirmation_for(token)
      cooldown = confirmation_for(token)
      unknown = confirmation_for("unknown-token")

      expect([ acted, cooldown, unknown ].map(&:first)).to all(eq(200))
      expect([ acted.last, cooldown.last, unknown.last ].uniq.size).to eq(1)
    end

    it "waits ten minutes between renewals of the same invitation" do
      expire(invitation)
      post portal_invitation_renewal_path(token)

      expect { post portal_invitation_renewal_path(token) }.not_to change(ApplicantInvitation, :count)

      travel_to(11.minutes.from_now) do
        expect { post portal_invitation_renewal_path(token) }.to change(ApplicantInvitation, :count).by(1)
      end
    end

    it "is limited to five requests per ten minutes per address" do
      5.times { post portal_invitation_renewal_path("unknown-token") }
      expect(response).to have_http_status(:ok)

      post portal_invitation_renewal_path("unknown-token")

      expect(response).to have_http_status(:too_many_requests)
    end

    it "logs each request without the token" do
      allow(SecurityEventLogger).to receive(:log)

      post portal_invitation_renewal_path("unknown-token")

      expect(SecurityEventLogger).to have_received(:log).with(event: "portal.invitation_renewal_requested", request: anything)
    end
  end
end
