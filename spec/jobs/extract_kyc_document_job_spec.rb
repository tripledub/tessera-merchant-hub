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

    context "when document_type is other" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :other,
          classification_status: :confirmed,
          status: :pending)
      end

      it "skips extraction instead of crashing on the schema-less ExtractionData::Generic fallback" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.status).to eq("pending")
        expect(document.result).to be_nil
        expect(Kyc::DocumentExtractorService).not_to have_received(:call)
      end
    end

    context "when document_type is processing_statement" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :processing_statement,
          classification_status: :confirmed,
          status: :pending)
      end

      it "skips extraction because processing statements use their own import pipeline" do
        described_class.new.perform(document.id)

        expect(document.reload.status).to eq("pending")
        expect(Kyc::DocumentExtractorService).not_to have_received(:call)
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

    # MH-320: ground truth verified directly against the real Claude
    # extraction endpoint for both specimen_utilitybill_*.pdf fixtures
    # (spec/fixtures/files) before writing these expectations — see
    # docs/qase.md's "synthetic specimen" discipline.
    context "when a utility bill's printed address is cleanly formatted" do
      let(:principal_with_address) do
        create(:kyc_principal,
          applicant: applicant,
          name: "Alex Testperson",
          address_line1: "12 High Street",
          city: "London",
          postcode: "SW1A 1AA",
          country: "United Kingdom")
      end

      let(:document) do
        create(:kyc_document, applicant: applicant, document_type: :utility_bill, classification_status: :confirmed)
      end

      before do
        principal_with_address
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Alex Testperson",
          "account_holder_address_line1" => "12 High Street",
          "account_holder_city" => "London",
          "account_holder_postcode" => "SW1A 1AA",
          "account_holder_country" => "United Kingdom",
          "provider" => "Utopia Power & Light",
          "provider_address" => "1 Substation Road, Utopia City, UT1 2AA, Republic of Utopia",
          "issue_date" => "2020-01-15",
          "account_number" => "UTL-0001-9284"
        )
      end

      it "matches the principal's address exactly" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.address_match_method).to eq("exact")
      end
    end

    # specimen_utilitybill_address_formatting.pdf prints the SAME address
    # with different casing, no punctuation, and a squished postcode
    # ("12 HIGH STREET LONDON SW1A1AA UNITED KINGDOM"). Verifying it against
    # the real Claude endpoint showed the model normalizes this back to
    # clean, correctly-split fields identical to the tidy fixture's — so the
    # extracted data below is (correctly) the same as the clean fixture's,
    # not a verbatim transcription of the messy printed text. This means the
    # known AddressMatcherService gap
    # (spec/services/address_matcher_service_spec.rb:74-79, where an
    # already-differently-formatted *string* handed directly to the matcher
    # scores only "fuzzy") does not reproduce for a real scanned document:
    # extraction normalizes the formatting away before the matcher ever sees
    # it. Documented per this ticket's AC3 as the actual, current behaviour.
    context "when a utility bill's printed address has different casing, punctuation, and postcode spacing" do
      let(:principal_with_address) do
        create(:kyc_principal,
          applicant: applicant,
          name: "Alex Testperson",
          address_line1: "12 High Street",
          city: "London",
          postcode: "SW1A 1AA",
          country: "United Kingdom")
      end

      let(:document) do
        create(:kyc_document, applicant: applicant, document_type: :utility_bill, classification_status: :confirmed)
      end

      before do
        principal_with_address
        # Ground truth from the real extraction endpoint: normalized, not
        # the verbatim "12 HIGH STREET LONDON SW1A1AA UNITED KINGDOM" printed
        # on the document.
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Alex Testperson",
          "account_holder_address_line1" => "12 High Street",
          "account_holder_city" => "London",
          "account_holder_postcode" => "SW1A 1AA",
          "account_holder_country" => "United Kingdom",
          "provider" => "Utopia Power & Light",
          "provider_address" => "1 Substation Road, Utopia City, UT1 2AA, Republic of Utopia",
          "issue_date" => "2020-01-15",
          "account_number" => "UTL-0001-9284"
        )
      end

      it "still matches the principal's address exactly, because extraction normalized the formatting" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.address_match_method).to eq("exact")
      end
    end

    context "when a bank account statement is matched to a principal without an address" do
      let(:principal_no_address) do
        create(:kyc_principal, applicant: applicant, name: "Pieter Bakker")
      end

      let(:document) do
        create(:kyc_document, applicant: applicant, document_type: :bank_account_statement, classification_status: :confirmed)
      end

      before do
        principal_no_address
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "account_holder" => "Pieter Bakker",
          "bank_name" => "ING",
          "account_holder_address_line1" => "Willem Augustinstraat 190",
          "account_holder_city" => "Amsterdam",
          "account_holder_postcode" => "1061 MJ",
          "account_holder_country" => "Netherlands"
        )
      end

      it "matches the principal by account_holder (not full_name)" do
        described_class.new.perform(document.id)
        expect(document.reload.kyc_principal).to eq(principal_no_address)
      end

      it "populates the principal's address from the structured bank statement fields" do
        described_class.new.perform(document.id)
        principal_no_address.reload
        expect(principal_no_address.address_line1).to eq("Willem Augustinstraat 190")
        expect(principal_no_address.city).to eq("Amsterdam")
        expect(principal_no_address.postcode).to eq("1061 MJ")
        expect(principal_no_address.country).to eq("Netherlands")
      end

      it "stores address_match_method and address_match_confidence" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.address_match_method).to eq("exact")
        expect(document.address_match_confidence).to be_present
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

    context "when a validity policy is in effect for the document type" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport",
          effective_from: 1.year.ago.to_date,
          mode: :expires,
          required_dates: [ "expiry" ]
        )
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Jane Smith",
          "expiry_date" => "2030-06-15"
        )
      end

      it "merges validity_dates into the same update as the rest of the extraction result" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.validity_dates["expiry"]["raw"]).to eq("2030-06-15")
        expect(document.validity_dates["expiry"]["normalized"]).to eq("2030-06-15")
        expect(document.validity_dates["expiry"]["provenance"]).to eq("ai_extraction")
      end

      it "still completes the existing classification/principal behaviour unchanged" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.status).to eq("complete")
        expect(document.kyc_principal).to be_present
      end
    end

    # MH-306: a passport whose MRZ agrees with the printed expiry is
    # auto-accepted end to end — no staff confirmation needed.
    context "when the passport's MRZ expiry agrees with the printed expiry" do
      let(:agreeing_line2) { "AB12345671GBR8503150F3006151<<<<<<<<<<<<<<04" }

      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport",
          effective_from: 1.year.ago.to_date,
          mode: :expires,
          required_dates: [ "expiry" ]
        )
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Jane Smith",
          "expiry_date" => "2030-06-15",
          "mrz_line2" => agreeing_line2
        )
      end

      it "does not require validity confirmation and records the extracted source" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.validity_confirmation_required).to be(false)
        expect(document.validity_dates["expiry"]["confidence"]).to eq(1.0)
      end

      it "persists the MRZ-derived confidence on extracted_data too, alongside the raw MRZ" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.extracted_data["expiry_date_confidence"]).to eq(1.0)
        expect(document.extracted_data["mrz_line2"]).to eq(agreeing_line2)
      end
    end

    context "when the passport's MRZ expiry disagrees with the printed expiry" do
      let(:agreeing_line2) { "AB12345671GBR8503150F3006151<<<<<<<<<<<<<<04" }

      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport",
          effective_from: 1.year.ago.to_date,
          mode: :expires,
          required_dates: [ "expiry" ]
        )
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Jane Smith",
          "expiry_date" => "2031-06-15",
          "mrz_line2" => agreeing_line2
        )
      end

      it "still requires validity confirmation, exactly like a document with no MRZ at all" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.validity_confirmation_required).to be(true)
        expect(document.validity_dates["expiry"]["confidence"]).to be_nil
      end
    end

    context "when the document type has no resolvable validity policy (outside rollout)" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :driving_licence,
          classification_status: :confirmed)
      end

      before do
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "full_name" => "Jane Smith",
          "expiry_date" => "2030-06-15"
        )
      end

      it "leaves validity fields inert" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.validity_dates).to eq({})
        expect(document.validity_confirmation_required).to be(false)
      end
    end

    context "when extraction fails entirely for a document type with a validity policy" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport",
          effective_from: 1.year.ago.to_date,
          mode: :expires,
          required_dates: [ "expiry" ]
        )
        allow(Kyc::DocumentExtractorService).to receive(:call)
          .and_raise(Kyc::DocumentExtractorService::Error, "Inference failed")
      end

      it "does not mark the document as needing validity confirmation or fabricate validity dates" do
        described_class.new.perform(document.id)
        document.reload

        expect(document.status).to eq("error")
        expect(document.validity_dates).to eq({})
        expect(document.validity_confirmation_required).to be(false)
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

  describe "#perform for a proof_of_domain_ownership document" do
    let(:document) do
      create(:kyc_document,
        applicant: applicant,
        document_type: :proof_of_domain_ownership,
        classification_status: :confirmed,
        status: :pending)
    end

    let(:extracted_domains) { %w[example.com other-site.net] }

    before do
      allow(Kyc::DomainExtractorService).to receive(:call).and_return(extracted_domains)
    end

    it "extracts domains with the domain extractor, not the field-schema extractor" do
      described_class.new.perform(document.id)

      expect(Kyc::DomainExtractorService).to have_received(:call).with(document)
      expect(Kyc::DocumentExtractorService).not_to have_received(:call)
    end

    it "completes the document instead of leaving it pending (MH-290)" do
      described_class.new.perform(document.id)

      document.reload
      expect(document.status).to eq("complete")
      expect(document.extracted_data).to eq("domains" => extracted_domains)
    end

    it "creates a pending, extracted candidate domain per result with the document as evidence" do
      expect { described_class.new.perform(document.id) }
        .to change { applicant.applicant_domains.count }.by(2)

      domains = applicant.applicant_domains.order(:name)
      expect(domains.map(&:name)).to eq(%w[example.com other-site.net])
      expect(domains).to all(be_pending.and(be_source_extracted))
      expect(domains.map(&:evidence_documents)).to all(contain_exactly(document))
    end

    it "keeps an existing domain's status, whatever its case, and adds the document as evidence" do
      accepted = create(:applicant_domain, applicant: applicant, name: "Example.com")

      expect { described_class.new.perform(document.id) }
        .to change { applicant.applicant_domains.count }.by(1)

      expect(accepted.reload).to be_accepted.and(be_source_manual)
      expect(accepted.evidence_documents).to contain_exactly(document)
    end

    it "broadcasts each newly created domain to the applicant's Domains tab (MH-328)" do
      stream = "applicant_#{applicant.id}_domains"
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      described_class.new.perform(document.id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
        .with(stream, hash_including(target: "applicant-domains-list")).twice
    end

    it "does not broadcast a domain the applicant already had" do
      create(:applicant_domain, applicant: applicant, name: "Example.com")
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      described_class.new.perform(document.id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
        .with(anything, hash_including(locals: { applicant_domain: an_object_having_attributes(name: "other-site.net") })).once
    end

    it "does not bring back a rejected domain on re-extraction" do
      rejected = create(:applicant_domain, applicant: applicant, name: "example.com", review_status: :rejected)

      described_class.new.perform(document.id)

      expect(rejected.reload).to be_rejected
      expect(applicant.applicant_domains.where("lower(name) = ?", "example.com").count).to eq(1)
    end

    it "is idempotent when run twice" do
      described_class.new.perform(document.id)

      expect { described_class.new.perform(document.id) }
        .not_to change { applicant.applicant_domains.count }
    end

    it "only affects the applicant that owns the document" do
      other = create(:applicant)
      create(:applicant_domain, applicant: other, name: "example.com")

      described_class.new.perform(document.id)

      expect(applicant.applicant_domains.pluck(:name)).to match_array(extracted_domains)
      expect(other.applicant_domains.count).to eq(1)
    end

    context "when the document evidences no domains" do
      let(:extracted_domains) { [] }

      it "completes with no domains created" do
        expect { described_class.new.perform(document.id) }
          .not_to change(ApplicantDomain, :count)

        expect(document.reload.status).to eq("complete")
      end
    end

    context "when extraction fails" do
      before do
        allow(Kyc::DomainExtractorService).to receive(:call)
          .and_raise(Kyc::DomainExtractorService::Error, "Inference failed: boom")
      end

      it "marks the document as errored with the message and creates no domains" do
        expect { described_class.new.perform(document.id) }
          .not_to change(ApplicantDomain, :count)

        document.reload
        expect(document.status).to eq("error")
        expect(document.result).to eq("error" => "Inference failed: boom")
      end
    end

    context "when the classification is not confirmed" do
      let(:document) do
        create(:kyc_document,
          applicant: applicant,
          document_type: :proof_of_domain_ownership,
          classification_status: :ai_suggested,
          status: :pending)
      end

      it "does not extract" do
        described_class.new.perform(document.id)

        expect(Kyc::DomainExtractorService).not_to have_received(:call)
        expect(document.reload.status).to eq("pending")
      end
    end
  end
end
