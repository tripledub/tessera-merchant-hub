# frozen_string_literal: true

require "rails_helper"

# ICAO 9303 published specimen check-digit vector (MH-309 AC6): document
# number L898902C3 -> 6, DOB 740812 -> 2, expiry 120415 -> 9.
RSpec.describe Kyc::Synthetic::Mrz do
  describe ".check_digit" do
    it "matches the ICAO specimen document-number check digit" do
      expect(described_class.check_digit("L898902C3")).to eq("6")
    end

    it "matches the ICAO specimen date-of-birth check digit" do
      expect(described_class.check_digit("740812")).to eq("2")
    end

    it "matches the ICAO specimen expiry check digit" do
      expect(described_class.check_digit("120415")).to eq("9")
    end

    it "treats the filler '<' as zero" do
      expect(described_class.check_digit("<<<<<<<<<<<<<<")).to eq("0")
    end
  end

  describe ".char_value" do
    it "returns the digit's own value" do
      expect(described_class.char_value("7")).to eq(7)
    end

    it "returns A-Z as 10-35" do
      expect(described_class.char_value("A")).to eq(10)
      expect(described_class.char_value("Z")).to eq(35)
    end

    it "returns 0 for the filler" do
      expect(described_class.char_value("<")).to eq(0)
    end
  end
end
