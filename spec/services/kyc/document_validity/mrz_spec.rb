# frozen_string_literal: true

require "rails_helper"

# MH-306: check-digit arithmetic verified against ICAO Doc 9303 Part 4's
# published TD3 worked example (not just our own passport generator), so the
# implementation is checked against an authoritative source:
#   P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
#   L898902C36UTO7408122F1204159ZE184226B<<<<<10
RSpec.describe Kyc::DocumentValidity::Mrz do
  describe ".check_digit" do
    it "matches the ICAO 9303 document number check digit" do
      expect(described_class.check_digit("L898902C3")).to eq("6")
    end

    it "matches the ICAO 9303 date of birth check digit" do
      expect(described_class.check_digit("740812")).to eq("2")
    end

    it "matches the ICAO 9303 date of expiry check digit" do
      expect(described_class.check_digit("120415")).to eq("9")
    end

    it "matches the ICAO 9303 composite check digit" do
      composite_input = "L898902C36" + "7408122" + "1204159ZE184226B<<<<<1"

      expect(described_class.check_digit(composite_input)).to eq("0")
    end

    it "treats '<' filler characters as zero" do
      expect(described_class.check_digit("<<<<<<")).to eq("0")
    end

    it "is case-insensitive for letters" do
      expect(described_class.check_digit("uto")).to eq(described_class.check_digit("UTO"))
    end
  end
end
