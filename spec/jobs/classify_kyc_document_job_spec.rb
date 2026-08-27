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
      let(:mock_chat) { instance_double(RubyLLM::Chat) }

      before do
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_doc.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: mock_chat))
        allow(mock_chat).to receive(:ask).and_return(
          instance_double(RubyLLM::Message, content: '{"document_type": "passport", "confidence": 0.75}')
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
        checklist = [
          { "category" => "identity", "subject" => "John Smith", "document_types" => %w[passport driving_licence],
            "label" => "Proof of identity for John Smith" }
        ]
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection,
          document_checklist: checklist)
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

    context "when auto_classified but document type is not on the checklist" do
      before do
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection,
          document_checklist: [
            { "category" => "corporate", "subject" => "company", "document_types" => %w[certificate_of_incorporation],
              "label" => "Certificate of incorporation" }
          ])
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

    context "when ai_suggested with onboarding in document_collection stage" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }

      before do
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_doc.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: mock_chat))
        allow(mock_chat).to receive(:ask).and_return(
          instance_double(RubyLLM::Message, content: '{"document_type": "passport", "confidence": 0.75}')
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
      let(:mock_chat) { instance_double(RubyLLM::Chat) }

      before do
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_doc.pdf"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: mock_chat))
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new("server error"))
      end

      it "transitions document to error" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("error")
        expect(document.result["error"]).to include("API error")
      end

      it "notifies Honeybadger with document context but not the raw exception" do
        allow(Honeybadger).to receive(:notify)

        described_class.new.perform(document.id)

        expect(Honeybadger).to have_received(:notify).with(
          "KYC document classification failed",
          context: {
            kyc_document_id: document.id,
            content_type: document.file.content_type,
            error_class: "DocumentClassifiers::AiFallback::Error"
          }
        )
      end

      # The exception's own #message can echo back fragments of the AI
      # model's response or the underlying API error body, which is derived
      # from the KYC document's own content. Prove a marker planted in that
      # message never reaches the third-party Honeybadger report.
      it "never includes the underlying error message in the Honeybadger report" do
        sensitive_marker = "SENSITIVE_PASSPORT_NUMBER_998877"
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(sensitive_marker))
        reported = []
        allow(Honeybadger).to receive(:notify) { |*args| reported << args }

        described_class.new.perform(document.id)

        expect(reported).not_to be_empty
        expect(reported.flatten.map(&:to_s).join).not_to include(sensitive_marker)
      end

      it "notifies Honeybadger even when the subsequent broadcast fails" do
        allow(Honeybadger).to receive(:notify)
        # The first broadcast_document call (status: processing, at the top
        # of #perform) must still succeed — only the one after the rescue
        # sets status: error should fail, to prove Honeybadger.notify (which
        # now runs before it) isn't skipped by that failure.
        call_count = 0
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do
          call_count += 1
          raise StandardError, "actioncable down" if call_count > 1
        end

        expect { described_class.new.perform(document.id) }.to raise_error(StandardError, "actioncable down")

        expect(Honeybadger).to have_received(:notify)
        expect(document.reload.status).to eq("error")
      end
    end

    context "when the attachment type is unsupported by the AI model" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }

      before do
        allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new("mystery_file.xyz"))
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: mock_chat))
        allow(mock_chat).to receive(:ask).and_raise(
          RubyLLM::UnsupportedAttachmentError.new("application/x-not-a-real-format")
        )
      end

      it "transitions the document to error instead of leaving it stuck in processing" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("error")
        expect(document.result["error"]).to match(/unsupported/i)
      end
    end
  end
end
