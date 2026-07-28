# frozen_string_literal: true

require "rails_helper"

# MH-198: surfaces expired/stale linked documents as blocking ("unmet"), and
# confirmation_required linked documents as a distinct, staff-resolvable
# blocking state, without disturbing entities whose linked documents have no
# resolvable validity policy (out of rollout).
RSpec.describe Kyc::Compliance::Rules::DocumentValidity, type: :service do
  subject(:rule) { described_class.new }

  let(:applicant) { create(:applicant) }
  let(:source_document) { create(:kyc_document, applicant: applicant) }
  let(:entity) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                  entity_type: :corporate, name: "Northwind Holdings Ltd")
  end

  def validity_dates_for(normalized:, confidence: 0.95)
    { "raw" => normalized, "normalized" => normalized, "confidence" => confidence, "provenance" => "ai_extraction" }
  end

  describe "#applies_to?" do
    it "is false when the entity has no linked documents" do
      expect(rule.applies_to?(entity)).to be(false)
    end

    it "is false when linked documents have no resolvable validity policy" do
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :driving_licence)
      expect(rule.applies_to?(entity)).to be(false)
    end

    it "is true when a linked document has a resolvable validity policy" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2020, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             validity_dates: { "expiry" => validity_dates_for(normalized: "2030-01-01") })

      expect(rule.applies_to?(entity)).to be(true)
    end
  end

  describe "#evaluate" do
    context "when there are no linked documents with a resolvable policy" do
      it "returns :not_applicable" do
        create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :driving_licence)

        expect(rule.evaluate(entity)).to be_not_applicable
      end
    end

    context "with a passport (expires policy)" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2020, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )
      end

      it "is :met for a valid document" do
        create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 2.years).iso8601) })

        result = rule.evaluate(entity)

        expect(result).to be_met
        expect(result.satisfied).to contain_exactly("passport")
      end

      it "is :met for an expiring_soon document" do
        create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 10).iso8601) })

        result = rule.evaluate(entity)

        expect(result).to be_met
      end

      it "is :unmet (blocking) for an expired document" do
        create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
               validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date - 1).iso8601) })

        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("passport")
        expect(result.blocks_automated_completion?).to be(true)
      end

      it "is :confirmation_required (blocking, but distinct from unmet) when no authoritative date exists" do
        create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
               validity_dates: { "expiry" => validity_dates_for(normalized: nil, confidence: nil) })

        result = rule.evaluate(entity)

        expect(result).to be_confirmation_required
        expect(result).not_to be_unmet
        expect(result.awaiting_confirmation).to contain_exactly("passport")
        expect(result.blocks_automated_completion?).to be(true)
      end
    end

    context "with a utility bill (freshness policy)" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
          mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
        )
      end

      it "is :unmet (blocking) for a stale document" do
        create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :utility_bill,
               validity_dates: { "issued" => validity_dates_for(normalized: (applicant.validity_reference_date - 4.months).iso8601) })

        result = rule.evaluate(entity)

        expect(result).to be_unmet
        expect(result.missing).to contain_exactly("utility_bill")
      end
    end

    it "does not create duplicate assessments across repeated evaluations" do
      Kyc::DocumentValidityPolicy.publish!(
        document_type: "passport", effective_from: Date.new(2020, 1, 1),
        mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
      )
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 2.years).iso8601) })

      rule.evaluate(entity)
      expect {
        described_class.new.evaluate(entity)
      }.not_to change(Kyc::DocumentValidityAssessment, :count)
    end
  end
end
