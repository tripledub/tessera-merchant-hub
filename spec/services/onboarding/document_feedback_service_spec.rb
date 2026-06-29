# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::DocumentFeedbackService do
  let(:applicant) { create(:applicant) }
  let(:session) do
    create(:onboarding_session,
      applicant: applicant,
      current_stage: :document_collection,
      document_checklist: checklist)
  end
  let(:principal) { create(:kyc_principal, applicant: applicant, name: "Alice Johnson", source: :applicant_declared) }
  let(:checklist) do
    [
      { "category" => "identity", "subject" => "Alice Johnson", "document_types" => %w[passport driving_licence],
        "label" => "Proof of identity for Alice Johnson" },
      { "category" => "proof_of_address", "subject" => "Alice Johnson", "document_types" => %w[utility_bill],
        "label" => "Proof of address for Alice Johnson" }
    ]
  end

  let(:document) do
    create(:kyc_document,
      applicant: applicant,
      document_type: :passport,
      status: :complete,
      kyc_principal: principal)
  end

  before do
    session
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
  end

  describe ".call" do
    it "returns early when no onboarding session exists" do
      applicant_without_session = create(:applicant)
      doc = create(:kyc_document, applicant: applicant_without_session, document_type: :passport, status: :complete)

      expect { described_class.call(doc) }.not_to change(OnboardingMessage, :count)
    end

    it "returns early when session is not in document_collection stage" do
      session.update!(current_stage: :company_info)

      expect { described_class.call(document) }.not_to change(OnboardingMessage, :count)
    end

    context "when document has an error" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :passport,
          status: :error)
      end

      it "creates a bot message about the problem" do
        described_class.call(document)

        message = OnboardingMessage.last
        expect(message.role).to eq("bot")
        expect(message.stage).to eq("document_collection")
        expect(message.content).to include("problem processing")
        expect(message.content).to include(document.file.filename.to_s)
      end
    end

    context "when match confidence is low" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :passport,
          status: :complete,
          match_confidence: 0.65,
          kyc_principal: principal)
      end

      it "creates a bot message about low confidence" do
        described_class.call(document)

        message = OnboardingMessage.last
        expect(message.content).to include("doesn't closely match")
      end
    end

    context "when extraction succeeds with outstanding items" do
      it "creates a message listing remaining items" do
        described_class.call(document)

        message = OnboardingMessage.last
        expect(message.content).to include("received and processed successfully")
        expect(message.content).to include("Still needed")
        expect(message.content).to include("Proof of address for Alice Johnson")
      end

      it "does not complete the session" do
        described_class.call(document)

        expect(session.reload.status).to eq("in_progress")
      end
    end

    context "when all documents are received" do
      before do
        # Receive both required documents
        create(:kyc_document, applicant: applicant, document_type: :utility_bill,
          status: :complete, kyc_principal: principal)
      end

      it "creates a completion message" do
        described_class.call(document)

        message = OnboardingMessage.last
        expect(message.content).to include("that's all the documents we need")
      end

      it "marks the session as completed" do
        described_class.call(document)

        expect(session.reload.status).to eq("completed")
      end
    end

    it "broadcasts the message via Turbo Streams" do
      described_class.call(document)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
        "onboarding_#{session.id}_documents",
        target: "onboarding_messages",
        partial: "onboarding/conversations/message",
        locals: hash_including(message: an_instance_of(OnboardingMessage))
      )
    end
  end
end
