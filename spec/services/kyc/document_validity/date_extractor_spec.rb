# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentValidity::DateExtractor do
  let(:reference_date) { Date.new(2026, 1, 1) }

  before do
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport",
      effective_from: Date.new(2025, 1, 1),
      mode: :expires,
      required_dates: [ "expiry" ],
      blocking: true,
      enabled: true
    )

    Kyc::DocumentValidityPolicy.publish!(
      document_type: "utility_bill",
      effective_from: Date.new(2025, 1, 1),
      mode: :freshness,
      required_dates: [ "issued" ],
      max_age_months: 3,
      blocking: true,
      enabled: true
    )
  end

  describe ".call" do
    context "with a valid, high-confidence date" do
      it "returns raw, normalized, confidence, and provenance and does not require confirmation" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2030-06-15" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:raw]).to eq("2030-06-15")
        expect(expiry[:normalized]).to eq("2030-06-15")
        expect(expiry[:confidence]).to eq(0.95)
        expect(expiry[:provenance]).to eq("ai_extraction")
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end

    context "with a borderline (ambiguous) confidence exactly at the acceptance threshold" do
      it "accepts the date and does not require confirmation" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2030-06-15" },
          confidence: described_class::CONFIDENCE_THRESHOLD,
          reference_date: reference_date
        )

        expect(result[:validity_dates]["expiry"][:normalized]).to eq("2030-06-15")
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end

    context "with an invalid calendar date" do
      it "does not normalize the date and requires confirmation, preserving the raw value" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2027-02-31" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:raw]).to eq("2027-02-31")
        expect(expiry[:normalized]).to be_nil
        expect(result[:validity_confirmation_required]).to be(true)
      end

      it "does not silently correct a garbage string into a date" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "not-a-date" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:raw]).to eq("not-a-date")
        expect(expiry[:normalized]).to be_nil
        expect(result[:validity_confirmation_required]).to be(true)
      end

      it "does not accept an ambiguous non-ISO format by guessing" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "31/02/2027" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:raw]).to eq("31/02/2027")
        expect(expiry[:normalized]).to be_nil
        expect(result[:validity_confirmation_required]).to be(true)
      end
    end

    context "with a missing required date" do
      it "requires confirmation with nil raw and normalized values" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "full_name" => "Jane Smith" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:raw]).to be_nil
        expect(expiry[:normalized]).to be_nil
        expect(result[:validity_confirmation_required]).to be(true)
      end

      it "treats a blank string the same as missing" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:normalized]).to be_nil
        expect(result[:validity_confirmation_required]).to be(true)
      end
    end

    context "with a low-confidence date" do
      it "still records the normalized date but requires confirmation" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2030-06-15" },
          confidence: 0.4,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:normalized]).to eq("2030-06-15")
        expect(expiry[:confidence]).to eq(0.4)
        expect(result[:validity_confirmation_required]).to be(true)
      end

      it "requires confirmation when confidence is unavailable (nil)" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2030-06-15" },
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:normalized]).to eq("2030-06-15")
        expect(expiry[:confidence]).to be_nil
        expect(result[:validity_confirmation_required]).to be(true)
      end
    end

    context "with per-field confidence supplied on the raw extraction payload" do
      it "prefers the field-specific confidence over the document-level fallback" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2030-06-15", "expiry_date_confidence" => 0.2 },
          confidence: 0.95,
          reference_date: reference_date
        )

        expiry = result[:validity_dates]["expiry"]
        expect(expiry[:confidence]).to eq(0.2)
        expect(result[:validity_confirmation_required]).to be(true)
      end
    end

    context "with a utility bill requiring an issued date" do
      it "maps the 'issued' role to the issue_date schema field" do
        result = described_class.call(
          document_type: "utility_bill",
          raw_extraction: { "issue_date" => "2025-12-01" },
          confidence: 0.9,
          reference_date: reference_date
        )

        issued = result[:validity_dates]["issued"]
        expect(issued[:raw]).to eq("2025-12-01")
        expect(issued[:normalized]).to eq("2025-12-01")
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end

    context "when no policy resolves for the document type" do
      it "returns an inert result" do
        result = described_class.call(
          document_type: "driving_licence",
          raw_extraction: { "expiry_date" => "2030-06-15" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expect(result[:validity_dates]).to eq({})
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end

    context "when the only applicable policy is disabled" do
      it "returns an inert result" do
        Kyc::DocumentValidityPolicy.where(document_type: "passport").update_all(enabled: false)

        result = described_class.call(
          document_type: "passport",
          raw_extraction: { "expiry_date" => "2030-06-15" },
          confidence: 0.95,
          reference_date: reference_date
        )

        expect(result[:validity_dates]).to eq({})
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end

    context "when raw_extraction is nil (extraction failed before this point)" do
      it "returns an inert result rather than fabricating missing-date confirmation state" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: nil,
          confidence: 0.95,
          reference_date: reference_date
        )

        expect(result[:validity_dates]).to eq({})
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end

    context "when raw_extraction is empty" do
      it "returns an inert result" do
        result = described_class.call(
          document_type: "passport",
          raw_extraction: {},
          confidence: 0.95,
          reference_date: reference_date
        )

        expect(result[:validity_dates]).to eq({})
        expect(result[:validity_confirmation_required]).to be(false)
      end
    end
  end
end
