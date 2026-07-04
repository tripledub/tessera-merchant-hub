# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingChannel, type: :channel do
  let(:applicant)      { create(:applicant) }
  let(:session)        { create(:onboarding_session, applicant: applicant) }
  let(:applicant_user) { create(:applicant_user, applicant: applicant) }

  before { stub_connection current_applicant_user: applicant_user }

  def valid_token(session_id)
    Rails.application.message_verifier(:cable_auth).generate(
      { "session_id" => session_id, "user_id" => applicant_user.id },
      expires_in: 1.hour
    )
  end

  describe "#subscribed" do
    context "when the session belongs to the authenticated user's applicant" do
      it "accepts the subscription and streams from the session channel" do
        subscribe session_id: session.id, token: valid_token(session.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("onboarding:#{session.id}")
      end
    end

    context "when the token was issued for a different session" do
      let(:other_session) { create(:onboarding_session, applicant: create(:applicant)) }

      it "rejects the subscription" do
        subscribe session_id: session.id, token: valid_token(other_session.id)
        expect(subscription).to be_rejected
      end
    end

    context "when no token is provided" do
      it "rejects the subscription" do
        subscribe session_id: session.id
        expect(subscription).to be_rejected
      end
    end

    context "when the session does not exist" do
      it "rejects the subscription" do
        subscribe session_id: 0, token: valid_token(0)
        expect(subscription).to be_rejected
      end
    end
  end
end
