# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClassifyKycDocumentJob, type: :job do
  let(:applicant) { create(:applicant) }
  let(:document)  { create(:kyc_document, applicant: applicant) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "when filename matches a rule-based classifier" do
      before do
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("John Smith - Passport - 16-11-2027.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
      end

      it "classifies the document and sets auto_classified status" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.document_type).to eq("passport")
        expect(document.classification_status).to eq("auto_classified")
        expect(document.classification_confidence).to eq(1.0)
        expect(document.classification_method).to eq("rule_based")
        expect(document.status).to eq("pending")
      end

      it "broadcasts twice (processing + classified)" do
        described_class.new.perform(document.id)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice
      end
    end

    context "when filename does not match any rule-based classifier" do
      before do
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-key")
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_doc.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)

        client = instance_double(Anthropic::Client)
        messages = instance_double(Anthropic::Resources::Messages)
        allow(Anthropic::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)
        allow(messages).to receive(:create).and_return(
          instance_double(
            Anthropic::Models::Message,
            content: [ instance_double(Anthropic::Models::TextBlock, text: '{"document_type": "passport", "confidence": 0.75}') ]
          )
        )
      end

      it "falls back to AI classifier with ai_suggested status" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.classification_status).to eq("ai_suggested")
        expect(document.classification_confidence).to eq(0.75)
        expect(document.classification_method).to eq("ai")
      end
    end

    context "when auto_classified with onboarding in document_collection stage" do
      before do
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("John Smith - Passport - 16-11-2027.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
      end

      it "confirms the classification and enqueues extraction" do
        expect {
          described_class.new.perform(document.id)
        }.to have_enqueued_job(ExtractKycDocumentJob).with(document.id)

        document.reload
        expect(document.classification_status).to eq("confirmed")
      end
    end

    context "when ai_suggested with onboarding in document_collection stage" do
      before do
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-key")
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_doc.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)

        client = instance_double(Anthropic::Client)
        messages = instance_double(Anthropic::Resources::Messages)
        allow(Anthropic::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)
        allow(messages).to receive(:create).and_return(
          instance_double(
            Anthropic::Models::Message,
            content: [ instance_double(Anthropic::Models::TextBlock, text: '{"document_type": "passport", "confidence": 0.75}') ]
          )
        )
      end

      it "does not auto-confirm or enqueue extraction" do
        expect {
          described_class.new.perform(document.id)
        }.not_to have_enqueued_job(ExtractKycDocumentJob)

        document.reload
        expect(document.classification_status).to eq("ai_suggested")
      end
    end

    context "without an onboarding session" do
      before do
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("John Smith - Passport - 16-11-2027.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
      end

      it "does not auto-confirm or enqueue extraction" do
        expect {
          described_class.new.perform(document.id)
        }.not_to have_enqueued_job(ExtractKycDocumentJob)

        document.reload
        expect(document.classification_status).to eq("auto_classified")
      end
    end

    context "when classification fails" do
      before do
        allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return("test-key")
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_doc.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)

        client = instance_double(Anthropic::Client)
        messages = instance_double(Anthropic::Resources::Messages)
        allow(Anthropic::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)
        allow(messages).to receive(:create).and_raise(
          Anthropic::Errors::APIError.new(url: nil, status: 500, body: nil, message: "server error")
        )
      end

      it "transitions document to error" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("error")
        expect(document.result["error"]).to include("API error")
      end
    end
  end
end
