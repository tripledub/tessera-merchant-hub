# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::ChatCommandHandler do
  describe ".call" do
    it "responds to help with the list of supported commands" do
      session = create(:onboarding_session, current_stage: :company_info)

      result = described_class.call(session: session, stage: :company_info, command: :help)

      expect(result[:bot_message]).to include("help")
      expect(result[:bot_message]).to include("save")
      expect(result[:bot_message]).to include("skip")
      expect(result[:extracted_data]).to eq({})
      expect(result[:stage_changed]).to be(false)
      expect(session.onboarding_messages.last).to have_attributes(role: "bot", stage: "company_info")
    end

    it "responds to save by confirming progress is kept and can be resumed" do
      session = create(:onboarding_session, current_stage: :business_activity)

      result = described_class.call(session: session, stage: :business_activity, command: :save)

      expect(result[:bot_message]).to match(/saved/i)
      expect(result[:bot_message]).to match(/come back|resume/i)
      expect(session.onboarding_messages.last.content).to eq(result[:bot_message])
    end

    it "blocks skip outside the document collection stage" do
      session = create(:onboarding_session, current_stage: :company_info)

      result = described_class.call(session: session, stage: :company_info, command: :skip)

      expect(result[:bot_message]).to match(/not available|isn.t available/i)
      expect(session.onboarding_messages.last.stage).to eq("company_info")
    end

    it "defers the first outstanding checklist item when skip is used during document collection" do
      applicant = create(:applicant_user).applicant
      create(:kyc_principal, applicant: applicant, name: "Jane Smith", source: :applicant_declared)
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)

      result = described_class.call(session: session, stage: :document_collection, command: :skip)

      expect(result[:bot_message]).to include("Noted")
      expect(session.reload.document_checklist.first["deferred"]).to be(true)
    end

    it "tells the applicant there is nothing left to skip once all items are received or deferred" do
      applicant = create(:applicant_user).applicant
      session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      Onboarding::DocumentCollectionService.generate_checklist(session)
      session.document_checklist.each { |item| item["deferred"] = true }
      session.save!

      result = described_class.call(session: session, stage: :document_collection, command: :skip)

      expect(result[:bot_message]).to match(/nothing left to skip/i)
    end
  end
end
