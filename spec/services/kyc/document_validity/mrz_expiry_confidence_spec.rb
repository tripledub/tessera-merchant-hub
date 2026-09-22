# frozen_string_literal: true

require "rails_helper"

# MH-306: MRZ line 2 fixtures below are for a synthetic passport (document
# TEST00001, DOB 1980-03-15, expiry 2028-09-21) — the same one already used
# for MH-309/MH-314's committed specimen PDF, so these strings are exactly
# what the real extraction prompt returns for that fixture.
RSpec.describe Kyc::DocumentValidity::MrzExpiryConfidence do
  # Valid MRZ, expiry field "280921" agreeing with the printed 2028-09-21.
  let(:agreeing_line2) { "TEST000017UTO8003155M2809218<<<<<<<<<<<<<<02" }

  describe ".enrich" do
    context "with a passport whose MRZ expiry agrees with the printed expiry" do
      let(:raw_extraction) { { "expiry_date" => "2028-09-21", "mrz_line2" => agreeing_line2 } }

      it "adds expiry_date_confidence at the auto-accept level" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result["expiry_date_confidence"]).to eq(1.0)
      end

      it "leaves every other key untouched" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result).to include(raw_extraction)
      end
    end

    context "when the printed expiry disagrees with the MRZ expiry" do
      let(:raw_extraction) { { "expiry_date" => "2029-09-21", "mrz_line2" => agreeing_line2 } }

      it "does not add a confidence key" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result).not_to have_key("expiry_date_confidence")
      end
    end

    context "when the MRZ's own expiry check digit is invalid" do
      let(:corrupted_line2) { "TEST000017UTO8003155M2809211<<<<<<<<<<<<<<02" } # check digit flipped 8 -> 1
      let(:raw_extraction) { { "expiry_date" => "2028-09-21", "mrz_line2" => corrupted_line2 } }

      it "does not add a confidence key, even though the printed date looks right" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result).not_to have_key("expiry_date_confidence")
      end
    end

    context "when there is no MRZ at all" do
      let(:raw_extraction) { { "expiry_date" => "2028-09-21", "mrz_line2" => nil } }

      it "does not add a confidence key" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result).not_to have_key("expiry_date_confidence")
      end
    end

    context "when the MRZ line is the wrong length (garbled transcription)" do
      let(:raw_extraction) { { "expiry_date" => "2028-09-21", "mrz_line2" => "TEST000017UTO<<<" } }

      it "does not add a confidence key" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result).not_to have_key("expiry_date_confidence")
      end
    end

    context "when the printed expiry is missing or unparseable" do
      let(:raw_extraction) { { "expiry_date" => nil, "mrz_line2" => agreeing_line2 } }

      it "does not add a confidence key" do
        result = described_class.enrich(document_type: "passport", raw_extraction: raw_extraction)

        expect(result).not_to have_key("expiry_date_confidence")
      end
    end

    context "with a document type other than passport" do
      let(:raw_extraction) { { "expiry_date" => "2028-09-21", "mrz_line2" => agreeing_line2 } }

      it "returns raw_extraction unchanged, even if MRZ-shaped fields happen to be present" do
        result = described_class.enrich(document_type: "driving_licence", raw_extraction: raw_extraction)

        expect(result).to equal(raw_extraction)
      end
    end

    context "with a blank raw_extraction" do
      it "returns it unchanged" do
        expect(described_class.enrich(document_type: "passport", raw_extraction: {})).to eq({})
      end
    end
  end
end
