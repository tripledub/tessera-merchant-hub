# frozen_string_literal: true

require "rails_helper"

RSpec.describe AddressMatcherService do
  let(:principal) do
    build(:kyc_principal,
      address_line1: "12 High Street",
      address_line2: nil,
      city:          "London",
      postcode:      "SW1A 1AA",
      country:       "United Kingdom")
  end

  def call(extracted_address)
    described_class.call(principal: principal, extracted_address: extracted_address)
  end

  describe ".call" do
    context "when extracted address is blank" do
      it "returns nil match" do
        result = call(nil)
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end

      it "returns nil match for empty string" do
        result = call("")
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end

    context "when principal has no stored address" do
      let(:principal) { build(:kyc_principal, address_line1: nil, address_line2: nil, city: nil, postcode: nil, country: nil) }

      it "returns nil match" do
        result = call("12 High Street, London, SW1A 1AA")
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end

    context "with an exact match" do
      it "returns exact when strings are identical" do
        result = call("12 High Street, London, SW1A 1AA, United Kingdom")
        expect(result.match_method).to eq("exact")
        expect(result.match_confidence).to eq(1.0)
      end

      it "is case-insensitive" do
        result = call("12 HIGH STREET, LONDON, SW1A 1AA, UNITED KINGDOM")
        expect(result.match_method).to eq("exact")
      end

      it "normalises abbreviations — St → street" do
        result = call("12 High St, London, SW1A 1AA, United Kingdom")
        expect(result.match_method).to eq("exact")
      end

      it "normalises abbreviations — Rd → road" do
        principal2 = build(:kyc_principal,
          address_line1: "5 Oak Road", city: "Manchester", postcode: "M1 1AB", country: "United Kingdom")
        result = described_class.call(principal: principal2, extracted_address: "5 Oak Rd, Manchester, M1 1AB, United Kingdom")
        expect(result.match_method).to eq("exact")
      end
    end

    context "with a fuzzy match" do
      it "returns fuzzy for close but not identical addresses" do
        result = call("12 High Street London SW1A1AA United Kingdom")
        expect(result.match_method).to eq("fuzzy")
        expect(result.match_confidence).to be_between(0.80, 0.98)
      end
    end

    context "with no match" do
      it "returns nil when addresses are clearly different" do
        result = call("99 Fake Road, Manchester, M1 1ZZ, United Kingdom")
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end
  end
end
