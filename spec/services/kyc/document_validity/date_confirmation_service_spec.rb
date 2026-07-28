# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentValidity::DateConfirmationService do
  let_it_be(:actor) { create(:user, :psp_admin) }

  let(:document) do
    create(:kyc_document, validity_dates: {
      "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01", "confidence" => 0.95,
                    "provenance" => "ai_extraction" }
    })
  end

  describe ".call" do
    context "when confirming an unchanged extracted date" do
      it "succeeds and records the extracted value as both extracted and confirmed" do
        result = described_class.call(document: document, date_role: "expiry",
                                       confirmed_value: "2030-01-01", actor: actor)

        expect(result).to be_success
        confirmation = result.confirmation
        expect(confirmation.extracted_value).to eq(Date.new(2030, 1, 1))
        expect(confirmation.confirmed_value).to eq(Date.new(2030, 1, 1))
        expect(confirmation.confirmed_by).to eq(actor)
        expect(confirmation.reason).to be_blank
      end

      it "does not require a reason" do
        result = described_class.call(document: document, date_role: "expiry",
                                       confirmed_value: "2030-01-01", actor: actor)

        expect(result).to be_success
      end
    end

    context "when entering a missing date" do
      let(:document) { create(:kyc_document, validity_dates: {}) }

      it "succeeds without a reason and snapshots a nil extracted value" do
        result = described_class.call(document: document, date_role: "expiry",
                                       confirmed_value: "2032-05-01", actor: actor)

        expect(result).to be_success
        expect(result.confirmation.extracted_value).to be_nil
        expect(result.confirmation.confirmed_value).to eq(Date.new(2032, 5, 1))
      end
    end

    context "when correcting a changed date" do
      it "fails without a reason" do
        result = described_class.call(document: document, date_role: "expiry",
                                       confirmed_value: "2031-01-01", actor: actor)

        expect(result).not_to be_success
        expect(result.errors[:reason]).to be_present
      end

      it "succeeds with a non-blank reason and preserves both values" do
        result = described_class.call(document: document, date_role: "expiry",
                                       confirmed_value: "2031-01-01", reason: "Passport renewed since scan",
                                       actor: actor)

        expect(result).to be_success
        expect(result.confirmation.extracted_value).to eq(Date.new(2030, 1, 1))
        expect(result.confirmation.confirmed_value).to eq(Date.new(2031, 1, 1))
        expect(result.confirmation.reason).to eq("Passport renewed since scan")
      end
    end

    context "with a blank confirmed_value" do
      it "fails" do
        result = described_class.call(document: document, date_role: "expiry", confirmed_value: "", actor: actor)

        expect(result).not_to be_success
        expect(result.errors[:confirmed_value]).to be_present
      end
    end

    context "with an unparseable confirmed_value" do
      it "fails" do
        result = described_class.call(document: document, date_role: "expiry",
                                       confirmed_value: "not-a-date", actor: actor)

        expect(result).not_to be_success
        expect(result.errors[:confirmed_value]).to be_present
      end
    end

    it "creates a new audit row rather than mutating a previous confirmation" do
      first = described_class.call(document: document, date_role: "expiry",
                                    confirmed_value: "2030-01-01", actor: actor)
      second = described_class.call(document: document, date_role: "expiry",
                                     confirmed_value: "2031-01-01", reason: "Corrected", actor: actor)

      expect(second.confirmation.id).not_to eq(first.confirmation.id)
      expect(Kyc::DocumentDateConfirmation.where(kyc_document: document, date_role: "expiry").count).to eq(2)
      expect(first.confirmation.reload.confirmed_value).to eq(Date.new(2030, 1, 1))
    end

    it "does not itself flip validity_confirmation_required (out of scope for MH-196)" do
      document.update!(validity_confirmation_required: true)

      described_class.call(document: document, date_role: "expiry", confirmed_value: "2030-01-01", actor: actor)

      expect(document.reload.validity_confirmation_required).to be(true)
    end
  end
end
