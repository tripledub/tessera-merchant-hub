# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::CompaniesHouseName do
  describe ".normalize" do
    # Reorders only — casing is untouched. Case never matters to the caller
    # (PrincipalMatcherService downcases both sides before comparing), and
    # guessing at title-casing a surname risks mangling names it doesn't
    # understand (e.g. "O'BRIEN").
    it "rewrites SURNAME, Forenames into Forenames Surname" do
      expect(described_class.normalize("SAMPLE, Riley")).to eq("Riley SAMPLE")
    end

    it "handles multi-word forenames" do
      expect(described_class.normalize("EXAMPLESON, Morgan Lee")).to eq("Morgan Lee EXAMPLESON")
    end

    it "collapses extra whitespace around the comma" do
      expect(described_class.normalize("SAMPLE,   Riley")).to eq("Riley SAMPLE")
    end

    it "leaves a name with no comma unchanged" do
      expect(described_class.normalize("Riley Sample")).to eq("Riley Sample")
    end

    it "leaves blank input unchanged" do
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize("")).to eq("")
    end
  end
end
