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

      it "notifies Honeybadger with document context, cause: nil, but not the raw exception" do
        allow(Honeybadger).to receive(:notify)

        described_class.new.perform(document.id)

        expect(Honeybadger).to have_received(:notify).with(
          "KYC document classification failed",
          cause: nil,
          context: {
            kyc_document_id: document.id,
            content_type: document.file.content_type,
            error_class: "DocumentClassifiers::AiFallback::Error"
          }
        )
      end

      it "never includes the underlying error message in the Honeybadger report" do
        sensitive_marker = "SENSITIVE_PASSPORT_NUMBER_998877"
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(sensitive_marker))
        reported = []
        allow(Honeybadger).to receive(:notify) { |*args, **kwargs| reported << [ args, kwargs ] }

        described_class.new.perform(document.id)

        expect(reported).not_to be_empty
        expect(reported.flatten.map(&:to_s).join).not_to include(sensitive_marker)
      end

      # Mocking notify only proves what we sent, not what Honeybadger would
      # build ($! fallback only applies live, inside this rescue) — use the
      # real Notice pipeline via Honeybadger's Test backend, sync delivery.
      it "produces a Honeybadger notice with an empty cause chain and no sensitive content in its serialized payload" do
        original_backend = Honeybadger.config[:backend]
        original_sync = Honeybadger.config[:sync]
        Honeybadger.config[:backend] = "test"
        Honeybadger.config[:sync] = true
        sensitive_marker = "SENSITIVE_PASSPORT_NUMBER_998877"
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(sensitive_marker))

        described_class.new.perform(document.id)

        notice = Honeybadger::Backend::Test.notifications[:notices].last
        expect(notice.causes).to be_empty
        expect(notice.to_json).not_to include(sensitive_marker)
      ensure
        Honeybadger.config[:backend] = original_backend
        Honeybadger.config[:sync] = original_sync
        Honeybadger::Backend::Test.notifications[:notices].clear
      end

      it "notifies Honeybadger even when the subsequent broadcast fails" do
        allow(Honeybadger).to receive(:notify)
        raise_on_second_broadcast { raise StandardError, "actioncable down" }

        expect { described_class.new.perform(document.id) }
          .to raise_error(ClassifyKycDocumentJob::BroadcastAfterClassificationFailureError)

        expect(Honeybadger).to have_received(:notify)
        expect(document.reload.status).to eq("error")
      end

      it "does not let a broadcast failure escape carrying the original classification exception as its cause" do
        allow(Honeybadger).to receive(:notify)
        raise_on_second_broadcast { raise StandardError, "actioncable down" }

        escaped = perform_and_capture_escaped_error

        expect(escaped).to be_a(ClassifyKycDocumentJob::BroadcastAfterClassificationFailureError)
        expect(escaped.cause).to be_nil
      end

      # ActionView::Template::Error overrides #cause with an ivar set from $!
      # in its own #initialize — raise(..., cause: nil) can't suppress that.
      it "does not leak sensitive content from a real ActionView::Template::Error broadcast failure" do
        classification_marker = "SENSITIVE_CLASSIFICATION_MARKER"
        broadcast_marker = "SENSITIVE_BROADCAST_MARKER"
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(classification_marker))
        allow(Honeybadger).to receive(:notify)
        raise_on_second_broadcast do
          raise broadcast_marker
        rescue StandardError
          raise ActionView::Template::Error.new(nil)
        end

        escaped = perform_and_capture_escaped_error

        expect(escaped).to be_a(ClassifyKycDocumentJob::BroadcastAfterClassificationFailureError)
        expect(escaped.cause).to be_nil
        expect(escaped.message).not_to include(classification_marker)
        expect(escaped.message).not_to include(broadcast_marker)
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

    context "when an unmatched spreadsheet is uploaded" do
      before do
        document.file.attach(
          io: StringIO.new("fake spreadsheet content"),
          filename: "processing_statement.xlsx",
          content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
      end

      it "suggests a processing statement without routing it before confirmation" do
        extraction_jobs_before = ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == ExtractKycDocumentJob }
        expect { described_class.new.perform(document.id) }.not_to change(ProcessingStatement, :count)
        extraction_jobs_after = ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == ExtractKycDocumentJob }
        expect(extraction_jobs_after).to eq(extraction_jobs_before)

        document.reload
        expect(document.status).to eq("complete")
        expect(document.document_type).to eq("processing_statement")
        expect(document.classification_status).to eq("ai_suggested")
        expect(document.classification_method).to eq("spreadsheet_content_type")
        expect(document.result).to be_nil
        expect(document.processing_statement).to be_nil
      end
    end

    context "when a spreadsheet filename matches an existing rule" do
      before do
        document.file.attach(
          io: StringIO.new("fake spreadsheet content"),
          filename: "transaction extract.csv",
          content_type: "text/csv"
        )
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
      end

      it "keeps the rule-based classification and does not create a processing statement" do
        expect {
          described_class.new.perform(document.id)
        }.not_to change(ProcessingStatement, :count)

        expect(document.reload).to have_attributes(
          document_type: "transaction_extract",
          classification_method: "rule_based"
        )
      end
    end

    context "when the spreadsheet is uploaded during onboarding document collection" do
      before do
        document.file.attach(
          io: StringIO.new("fake spreadsheet content"),
          filename: "processing_statement.xlsx",
          content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
        allow(KycDocument).to receive(:find).with(document.id).and_return(document)
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      end

      it "does not auto-confirm or enqueue extraction" do
        expect {
          described_class.new.perform(document.id)
        }.not_to have_enqueued_job(ExtractKycDocumentJob)

        document.reload
        expect(document.classification_status).to eq("ai_suggested")
        expect(document.processing_statement).to be_nil
      end
    end
  end

  def raise_on_second_broadcast(&block)
    call_count = 0
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do
      call_count += 1
      block.call if call_count > 1
    end
  end

  def perform_and_capture_escaped_error
    described_class.new.perform(document.id)
    nil
  rescue StandardError => e
    e
  end
end
