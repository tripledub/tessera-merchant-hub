# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractKycDocumentJob, type: :job do
  let(:applicant) { create(:applicant) }
  let(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Smith") }
  let(:document) do
    create(:kyc_document,
      applicant: applicant,
      document_type: :passport,
      classification_status: :confirmed)
  end

  # Intentionally omits "document_type" — MH-173 regression: the real
  # Kyc::DocumentExtractorService response never includes this key, only
  # the extracted schema fields. PrincipalMatcherService must source
  # document_type from the KycDocument itself, not from this hash.
  let(:ocr_response) { { "full_name" => "Jane Smith" } }

  before do
    allow(Kyc::DocumentExtractorService).to receive(:call).and_return(ocr_response)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
  end

  describe "#perform" do
    it "transitions document to complete" do
      described_class.new.perform(document.id)
      document.reload
      expect(document.status).to eq("complete")
    end

    it "delegates to DocumentExtractorService" do
      described_class.new.perform(document.id)
      expect(Kyc::DocumentExtractorService).to have_received(:call).with(document)
    end

    it "auto-matches principal by full_name" do
      principal
      described_class.new.perform(document.id)
      expect(document.reload.kyc_principal).to eq(principal)
    end

    it "creates an unconfirmed principal from a passport when no match exists" do
      expect { described_class.new.perform(document.id) }
        .to change(KycPrincipal, :count).by(1)
      principal = document.reload.kyc_principal
      expect(principal).to be_present
      expect(principal).to be_unconfirmed
      expect(principal.name).to eq("Jane Smith")
    end

    it "uses DOB-aware matching for passports, falling through to fuzzy when DOB differs" do
      existing_principal = create(:kyc_principal, applicant: applicant, name: "Jane Smith", date_of_birth: "1970-01-01")
      allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
        { "full_name" => "Jane Smith", "date_of_birth" => "1995-05-05" }
      )

      described_class.new.perform(document.id)

      document.reload
      expect(document.kyc_principal).to eq(existing_principal)
      expect(document.match_method).to eq("fuzzy")
    end

    it "broadcasts document status and tab updates" do
      described_class.new.perform(document.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:twice)
    end

    it "broadcasts a toast notification on completion" do
      described_class.new.perform(document.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
        "applicant_#{applicant.id}_documents",
        target: "toast-container",
        partial: "shared/toast",
        locals: hash_including(type: :success)
      )
    end

    context "when classification is not confirmed" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :passport,
          classification_status: :auto_classified)
      end

      it "skips extraction" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("pending")
        expect(document.result).to be_nil
      end
    end

    context "when address matching runs for a utility bill with a principal present" do
      let(:principal_with_address) do
        create(:kyc_principal,
          applicant: applicant,
          name: "Jane Smith",
          address_line1: "12 High Street",
          city: "London",
          postcode: "SW1A 1AA",
          country: "United Kingdom")
      end

      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :utility_bill,
          classification_status: :confirmed)
      end

      before do
        principal_with_address
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Jane Smith",
          "account_holder_address_line1" => "12 High Street",
          "account_holder_city" => "London",
          "account_holder_postcode" => "SW1A 1AA",
          "account_holder_country" => "United Kingdom",
          "provider" => "Thames Water"
        )
      end

      it "stores address_match_method and address_match_confidence" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.address_match_method).to eq("exact")
        expect(document.address_match_confidence).to be_present
      end
    end

    context "when a utility bill is matched to a principal without an address" do
      let(:principal_no_address) do
        create(:kyc_principal, applicant: applicant, name: "Jane Smith")
      end

      let(:document) do
        create(:kyc_document, applicant: applicant, document_type: :utility_bill, classification_status: :confirmed)
      end

      before do
        principal_no_address
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Jane Smith",
          "account_holder_address_line1" => "42 Oak Avenue",
          "account_holder_city" => "Manchester",
          "account_holder_postcode" => "M1 2AB",
          "account_holder_country" => "United Kingdom",
          "provider" => "Northern Gas"
        )
      end

      it "populates the principal's address from the extracted data" do
        described_class.new.perform(document.id)
        principal_no_address.reload
        expect(principal_no_address.address_line1).to eq("42 Oak Avenue")
        expect(principal_no_address.city).to eq("Manchester")
        expect(principal_no_address.postcode).to eq("M1 2AB")
        expect(principal_no_address.country).to eq("United Kingdom")
      end

      it "does not overwrite an existing address" do
        principal_no_address.update!(address_line1: "Existing Address")
        described_class.new.perform(document.id)
        principal_no_address.reload
        expect(principal_no_address.address_line1).to eq("Existing Address")
      end
    end

    context "when document is a group_structure_chart" do
      let(:document) do
        create(:kyc_document, applicant: applicant, document_type: :group_structure_chart,
               classification_status: :confirmed)
      end

      before do
        allow(Kyc::GroupStructureExtractorService).to receive(:call)
      end

      it "delegates to Kyc::GroupStructureExtractorService" do
        described_class.new.perform(document.id)

        expect(Kyc::GroupStructureExtractorService).to have_received(:call).with(document)
      end

      it "marks the document as complete" do
        described_class.new.perform(document.id)

        expect(document.reload.status).to eq("complete")
      end

      it "does not call the generic document extractor" do
        described_class.new.perform(document.id)

        expect(Kyc::DocumentExtractorService).not_to have_received(:call)
      end
    end

    context "when an onboarding session exists in document_collection stage" do
      let!(:session) do
        create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
      end

      before do
        allow(Onboarding::DocumentFeedbackService).to receive(:call)
      end

      it "calls DocumentFeedbackService after successful extraction" do
        described_class.new.perform(document.id)

        expect(Onboarding::DocumentFeedbackService).to have_received(:call).with(document)
      end

      it "calls DocumentFeedbackService after failed extraction" do
        allow(Kyc::DocumentExtractorService).to receive(:call)
          .and_raise(Kyc::DocumentExtractorService::Error, "Inference failed")

        described_class.new.perform(document.id)

        expect(Onboarding::DocumentFeedbackService).to have_received(:call).with(document)
      end
    end

    context "when no onboarding session exists" do
      it "does not call DocumentFeedbackService" do
        allow(Onboarding::DocumentFeedbackService).to receive(:call)

        described_class.new.perform(document.id)

        expect(Onboarding::DocumentFeedbackService).not_to have_received(:call)
      end
    end

    context "when extraction fails" do
      before do
        allow(Kyc::DocumentExtractorService).to receive(:call)
          .and_raise(Kyc::DocumentExtractorService::Error, "Inference failed: model unavailable")
      end

      it "transitions document to error" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("error")
        expect(document.result["error"]).to include("model unavailable")
      end

      it "broadcasts an error toast notification" do
        described_class.new.perform(document.id)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          "applicant_#{applicant.id}_documents",
          target: "toast-container",
          partial: "shared/toast",
          locals: hash_including(type: :error)
        )
      end
    end
  end
end
