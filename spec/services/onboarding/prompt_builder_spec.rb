# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::PromptBuilder do
  describe ".build" do
    it "includes system instructions, current stage, and missing fields" do
      session = build(:onboarding_session, current_stage: :company_info)

      prompt = described_class.build(session: session)

      expect(prompt).to include("You are Tessera's KYC onboarding assistant")
      expect(prompt).to include("Do not skip stages")
      expect(prompt).to include("Current stage: company_info")
      expect(prompt).to include("Missing required fields:")
      expect(prompt).to include("company_name")
      expect(prompt).to include("country_of_incorporation")
    end

    it "includes collected stage data as JSON" do
      session = build(:onboarding_session, current_stage: :business_activity, stage_data: {
        "company_info" => {
          "company_name" => "Acme Ltd",
          "registration_number" => "12345678"
        }
      })

      prompt = described_class.build(session: session)

      expect(prompt).to include('"company_name": "Acme Ltd"')
      expect(prompt).to include('"registration_number": "12345678"')
    end

    it "includes recent message history in chronological order" do
      session = create(:onboarding_session)
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "First", created_at: 3.minutes.ago)
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "Second",
        created_at: 2.minutes.ago)
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "Third", created_at: 1.minute.ago)

      prompt = described_class.build(session: session)

      expect(prompt).to include("bot: First\napplicant: Second\nbot: Third")
    end

    it "limits recent message history" do
      session = create(:onboarding_session)
      7.times do |index|
        create(:onboarding_message, onboarding_session: session, role: :applicant, content: "Message #{index}")
      end

      prompt = described_class.build(session: session)

      expect(prompt).not_to include("Message 0")
      expect(prompt).to include("Message 2")
      expect(prompt).to include("Message 6")
    end

    it "includes JSON extraction instructions" do
      session = build(:onboarding_session, current_stage: :directors_ubos)

      prompt = described_class.build(session: session)

      expect(prompt).to include("Return only valid JSON")
      expect(prompt).to include('"bot_message"')
      expect(prompt).to include('"extracted_data"')
      expect(prompt).to include("Use null when no field value was provided")
    end
  end
end
