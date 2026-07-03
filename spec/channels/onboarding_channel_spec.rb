# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingChannel, type: :channel do
  let(:applicant)      { create(:applicant) }
  let(:session)        { create(:onboarding_session, applicant: applicant) }
  let(:applicant_user) { create(:applicant_user, applicant: applicant) }

  before { stub_connection current_applicant_user: applicant_user }

  describe "#subscribed" do
    context "when the session belongs to the authenticated user's applicant" do
      it "accepts the subscription and streams from the session channel" do
        subscribe session_id: session.id
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("onboarding:#{session.id}")
      end
    end

    context "when the session belongs to a different applicant" do
      let(:other_session) { create(:onboarding_session, applicant: create(:applicant)) }

      it "rejects the subscription" do
        subscribe session_id: other_session.id
        expect(subscription).to be_rejected
      end
    end

    context "when the session does not exist" do
      it "rejects the subscription" do
        subscribe session_id: 0
        expect(subscription).to be_rejected
      end
    end
  end
end
