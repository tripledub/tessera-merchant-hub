# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamOnboardingResponseJob, type: :job do
  it "calls ConversationEngine.respond with stream: true" do
    session = create(:onboarding_session)
    allow(Onboarding::ConversationEngine).to receive(:respond)

    described_class.perform_now(session.id, "Hello")

    expect(Onboarding::ConversationEngine).to have_received(:respond).with(
      session: session,
      user_message: "Hello",
      stream: true
    )
  end

  it "raises RecordNotFound for an unknown session" do
    expect {
      described_class.perform_now(0, "Hello")
    }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
