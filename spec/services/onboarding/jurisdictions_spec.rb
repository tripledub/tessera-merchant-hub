# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::Jurisdictions do
  describe ".jurisdiction_for" do
    it "recognises the countries we offer, however they are written" do
      expect([ "United Kingdom", "UK", " great britain ", "England", "GB" ].map { |c| described_class.jurisdiction_for(c) }).to all(eq("gb"))
      expect(described_class.jurisdiction_for("Malta")).to eq("mt")
      expect(described_class.jurisdiction_for("cyprus")).to eq("cy")
    end

    it "gives nil for any other country, or nothing" do
      expect(described_class.jurisdiction_for("France")).to be_nil
      expect(described_class.jurisdiction_for(nil)).to be_nil
      expect(described_class.jurisdiction_for("")).to be_nil
    end
  end

  describe ".country_for" do
    it "names the country for a jurisdiction the PSP chose" do
      expect(described_class.country_for("gb")).to eq("United Kingdom")
      expect(described_class.country_for(:mt)).to eq("Malta")
      expect(described_class.country_for("cy")).to eq("Cyprus")
    end

    it "gives nil for none" do
      expect(described_class.country_for(nil)).to be_nil
    end
  end
end
