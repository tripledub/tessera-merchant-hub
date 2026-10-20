# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::CompanyTypes do
  describe ".normalize" do
    it "keeps a key, whatever its case or spacing" do
      expect(described_class.normalize("limited_company")).to eq("limited_company")
      expect(described_class.normalize(" Sole_Trader ")).to eq("sole_trader")
    end

    it "maps the chip labels back to their keys" do
      described_class::KEYS.each do |key|
        expect(described_class.normalize(described_class.label(key))).to eq(key)
      end
    end

    it "maps common wording" do
      expect(described_class.normalize("Ltd")).to eq("limited_company")
      expect(described_class.normalize("private limited company")).to eq("limited_company")
      expect(described_class.normalize("public limited company")).to eq("plc")
      expect(described_class.normalize("Limited liability partnership")).to eq("llp")
      expect(described_class.normalize("self-employed")).to eq("sole_trader")
    end

    it "gives nil for anything else, so it is asked again" do
      expect(described_class.normalize("a charity")).to be_nil
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize("  ")).to be_nil
    end
  end

  describe ".registry_searchable?" do
    it "is true for limited companies, PLCs and LLPs only" do
      %w[limited_company plc llp].each { |key| expect(described_class.registry_searchable?(key)).to be(true) }
      %w[sole_trader partnership other].each { |key| expect(described_class.registry_searchable?(key)).to be(false) }
    end

    it "understands a label or wording as well as a key, and is false for the unknown" do
      expect(described_class.registry_searchable?("Limited company")).to be(true)
      expect(described_class.registry_searchable?("a charity")).to be(false)
      expect(described_class.registry_searchable?(nil)).to be(false)
    end
  end
end
