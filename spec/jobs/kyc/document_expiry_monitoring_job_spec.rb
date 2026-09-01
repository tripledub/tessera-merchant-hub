# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Kyc::DocumentExpiryMonitoringJob do
  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:principal) { create(:kyc_principal, applicant: applicant) }

  def validity_dates_for(normalized:, confidence: 0.95)
    { "raw" => normalized, "normalized" => normalized, "confidence" => confidence, "provenance" => "ai_extraction" }
  end

  def passport_document(expiry:, principal: nil, status: :complete)
    create(:kyc_document, document_type: "passport", applicant: applicant, kyc_principal: principal, status: status,
           classification_status: :confirmed,
           validity_dates: { "expiry" => validity_dates_for(normalized: expiry.iso8601) })
  end

  def requirement_for(document)
    Kyc::DocumentReplacementRequirement.current_for(document)
  end

  def synchronized_expiry_policy(reference_date)
    <<~YAML
      schema_version: 1
      sector: base
      requirements:
        - id: test.driving_licence_validity
          rule: document_validity
          outcome: blocking
          source: MH-212
          parameters:
            document_type: driving_licence
            version: 1
            effective_from: "#{reference_date.iso8601}"
            mode: expires
            required_dates:
              - expiry
            warning_thresholds:
              - 60
              - 15
            blocking: true
    YAML
  end

  def store_driving_licence_validity_translations
    I18n.backend.store_translations(
      :en,
      kyc: { policy_requirements: { test: { driving_licence_validity: {
        title: "Driving licence validity",
        guidance: "Confirm that the driving licence is current."
      } } } }
    )
  end

  def driving_licence_document(reference_date)
    create(:kyc_document, document_type: :driving_licence, applicant: applicant, status: :complete,
                           classification_status: :confirmed,
                           validity_dates: {
                             "expiry" => validity_dates_for(normalized: (reference_date + 45).iso8601)
                           })
  end

  before do
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport", effective_from: Date.new(2025, 1, 1),
      mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
    )
  end

  describe "document selection" do
    it "assesses an eligible active expires-mode document" do
      reference_date = Date.new(2026, 1, 1)
      eligible_doc = passport_document(expiry: reference_date + 10, principal: principal)

      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: eligible_doc)).to be_present
    end

    it "skips a freshness-mode document entirely" do
      reference_date = Date.new(2026, 1, 1)
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "utility_bill", effective_from: Date.new(2025, 1, 1),
        mode: :freshness, required_dates: [ "issued" ], max_age_months: 3
      )
      freshness_doc = create(:kyc_document, document_type: "utility_bill", applicant: applicant, status: :complete,
                              validity_dates: { "issued" => validity_dates_for(normalized: "2020-01-01") })

      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: freshness_doc)).to be_empty
    end

    it "skips a pending (not yet extracted) document" do
      reference_date = Date.new(2026, 1, 1)
      pending_doc = passport_document(expiry: reference_date + 10, status: :pending)

      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: pending_doc)).to be_empty
    end

    it "skips an errored document" do
      reference_date = Date.new(2026, 1, 1)
      error_doc = passport_document(expiry: reference_date + 10, status: :error)

      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: error_doc)).to be_empty
    end

    it "skips a superseded document" do
      reference_date = Date.new(2026, 1, 1)
      superseded_doc = passport_document(expiry: reference_date + 10)
      replacement = passport_document(expiry: reference_date + 400, principal: principal)
      superseded_doc.update!(superseded_by_kyc_document: replacement)

      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: superseded_doc)).to be_empty
    end

    it "never touches documents whose policy is disabled" do
      reference_date = Date.new(2026, 1, 1)
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "driving_licence", effective_from: Date.new(2025, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ], enabled: false
      )
      disabled_doc = create(:kyc_document, document_type: "driving_licence", applicant: applicant, status: :complete,
                             validity_dates: { "expiry" => validity_dates_for(normalized: (reference_date + 10).iso8601) })

      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: disabled_doc)).to be_empty
      expect(requirement_for(disabled_doc)).to be_nil
    end

    it "discovers a newly synchronized expires-mode document type without enqueueing an immediate run" do
      reference_date = Date.new(2026, 8, 21)
      document = driving_licence_document(reference_date)
      original_registry = Kyc::PolicyRegistry.instance
      store_driving_licence_validity_translations

      Dir.mktmpdir("kyc-policies") do |directory|
        Pathname(directory).join("base.yml").write(synchronized_expiry_policy(reference_date))
        registry = Kyc::PolicyRegistry.load!(path: directory)
        Kyc::PolicyRegistry.instance = registry

        expect {
          Kyc::PolicyValiditySync.call(registry: registry)
        }.not_to have_enqueued_job

        synchronized_policy = Kyc::DocumentValidityPolicy.find_by!(document_type: "driving_licence", version: 1)
        described_class.new.perform(reference_date: reference_date)

        expect(Kyc::DocumentValidityAssessment.current_for(document))
          .to have_attributes(kyc_document_validity_policy: synchronized_policy)
        expect(requirement_for(document)).to be_warned
      end
    ensure
      I18n.backend.reload!
      Kyc::PolicyRegistry.instance = original_registry
    end
  end

  describe "90-day warning" do
    it "creates the initial warning once when the document crosses the 90-day threshold" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date + 80, principal: principal)

      described_class.new.perform(reference_date: reference_date)

      requirement = requirement_for(document)
      expect(requirement).to be_warned
      expect(requirement.opened_at).to be_present
      expect(requirement.escalated_at).to be_nil
    end

    it "does not duplicate the warning, the assessment, or the requirement on retry the same day" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date + 80, principal: principal)

      described_class.new.perform(reference_date: reference_date)
      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: document).count).to eq(1)
      expect(Kyc::DocumentReplacementRequirement.where(kyc_document: document).count).to eq(1)
      expect(requirement_for(document)).to be_warned
    end
  end

  describe "30-day escalation" do
    it "escalates an existing warned requirement exactly once when crossing the 30-day threshold" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date + 80, principal: principal)
      described_class.new.perform(reference_date: reference_date)
      expect(requirement_for(document)).to be_warned

      later = reference_date + 55 # 80 - 55 = 25 days remaining -> crosses 30
      described_class.new.perform(reference_date: later)

      requirement = requirement_for(document)
      expect(requirement).to be_escalated
      expect(requirement.escalated_at).to be_present
    end

    it "does not duplicate escalation on retry the same day" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date + 10, principal: principal)

      described_class.new.perform(reference_date: reference_date)
      first_escalated_at = requirement_for(document).escalated_at
      described_class.new.perform(reference_date: reference_date)

      expect(Kyc::DocumentReplacementRequirement.where(kyc_document: document).count).to eq(1)
      expect(requirement_for(document).escalated_at).to eq(first_escalated_at)
    end

    it "creates a requirement already escalated when a document is first seen already past the 30-day threshold" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date + 10, principal: principal)

      described_class.new.perform(reference_date: reference_date)

      requirement = requirement_for(document)
      expect(requirement).to be_escalated
      expect(requirement.opened_at).to be_present
      expect(requirement.escalated_at).to be_present
    end
  end

  describe "after expiry" do
    it "keeps the requirement open once the document has expired" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date + 10, principal: principal)
      described_class.new.perform(reference_date: reference_date)
      expect(requirement_for(document)).to be_escalated

      described_class.new.perform(reference_date: reference_date + 20)

      requirement = requirement_for(document)
      expect(requirement).not_to be_closed
      expect(requirement).to be_escalated
    end

    it "opens an already-escalated requirement for a document expired with no prior warning" do
      reference_date = Date.new(2026, 1, 1)
      document = passport_document(expiry: reference_date - 5, principal: principal)

      described_class.new.perform(reference_date: reference_date)

      requirement = requirement_for(document)
      expect(requirement).to be_escalated
      expect(requirement).not_to be_closed
    end
  end

  describe "confirmed valid replacement" do
    it "closes the requirement and supersedes the prior document once a valid replacement exists" do
      reference_date = Date.new(2026, 1, 1)
      old_document = passport_document(expiry: reference_date + 10, principal: principal)
      described_class.new.perform(reference_date: reference_date)
      expect(requirement_for(old_document)).to be_escalated

      replacement = create(:kyc_document, document_type: "passport", applicant: applicant, kyc_principal: principal,
                            status: :complete, classification_status: :confirmed,
                            validity_dates: { "expiry" => validity_dates_for(normalized: (reference_date + 400).iso8601) },
                            created_at: 1.hour.from_now)

      described_class.new.perform(reference_date: reference_date + 1)

      old_document.reload
      requirement = requirement_for(old_document)
      expect(requirement).to be_closed
      expect(requirement.closed_at).to be_present
      expect(requirement.superseded_by_kyc_document).to eq(replacement)
      expect(old_document.superseded_by_kyc_document).to eq(replacement)
    end

    it "does not close the requirement when the newer document is not yet valid or expiring_soon" do
      reference_date = Date.new(2026, 1, 1)
      old_document = passport_document(expiry: reference_date + 10, principal: principal)
      described_class.new.perform(reference_date: reference_date)

      create(:kyc_document, document_type: "passport", applicant: applicant, kyc_principal: principal,
             status: :complete, classification_status: :confirmed,
             validity_dates: { "expiry" => validity_dates_for(normalized: (reference_date - 1).iso8601) },
             created_at: 1.hour.from_now)

      described_class.new.perform(reference_date: reference_date + 1)

      expect(requirement_for(old_document)).not_to be_closed
      expect(old_document.reload.superseded_by_kyc_document_id).to be_nil
    end

    it "keeps replacement history auditable after closing" do
      reference_date = Date.new(2026, 1, 1)
      old_document = passport_document(expiry: reference_date + 10, principal: principal)
      described_class.new.perform(reference_date: reference_date)
      requirement_id = requirement_for(old_document).id

      create(:kyc_document, document_type: "passport", applicant: applicant, kyc_principal: principal,
             status: :complete, classification_status: :confirmed,
             validity_dates: { "expiry" => validity_dates_for(normalized: (reference_date + 400).iso8601) },
             created_at: 1.hour.from_now)
      described_class.new.perform(reference_date: reference_date + 1)

      expect(Kyc::DocumentReplacementRequirement.find(requirement_id)).to be_closed
      expect(Kyc::DocumentReplacementRequirement.count).to eq(1)
    end
  end

  describe "freshness exclusion" do
    it "never creates a requirement or new assessment for a freshness-mode document, even when stale" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "utility_bill", effective_from: Date.new(2025, 1, 1),
        mode: :freshness, required_dates: [ "issued" ], max_age_months: 3
      )
      document = create(:kyc_document, document_type: "utility_bill", applicant: applicant, status: :complete,
                         validity_dates: { "issued" => validity_dates_for(normalized: "2020-01-01") })

      described_class.new.perform(reference_date: Date.new(2026, 1, 1))

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: document)).to be_empty
      expect(requirement_for(document)).to be_nil
    end
  end

  describe "disabled rollout" do
    it "never creates assessments or requirements for a document type with no enabled policy" do
      unpolicied_doc = create(:kyc_document, document_type: "bank_account_statement", applicant: applicant,
                               status: :complete)

      described_class.new.perform(reference_date: Date.new(2026, 1, 1))

      expect(Kyc::DocumentValidityAssessment.where(kyc_document: unpolicied_doc)).to be_empty
      expect(requirement_for(unpolicied_doc)).to be_nil
    end
  end
end
