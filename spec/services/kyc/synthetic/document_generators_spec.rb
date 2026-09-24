# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Synthetic::DocumentGenerators do
  describe ".for" do
    it "resolves 'passport' to Kyc::Synthetic::PassportPdf" do
      expect(described_class.for("passport")).to eq(Kyc::Synthetic::PassportPdf)
    end

    it "raises for an unknown document type" do
      expect { described_class.for("nonsense") }.to raise_error(ArgumentError)
    end
  end

  describe ".types" do
    it "includes passport" do
      expect(described_class.types).to include("passport")
    end
  end
end
