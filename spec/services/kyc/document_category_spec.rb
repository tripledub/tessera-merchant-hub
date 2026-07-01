# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentCategory do
  describe ".for" do
    it "returns :identity for passport" do
      expect(described_class.for("passport")).to eq(:identity)
    end

    it "returns :identity for driving_licence" do
      expect(described_class.for("driving_licence")).to eq(:identity)
    end

    it "returns :proof_of_address for utility_bill" do
      expect(described_class.for("utility_bill")).to eq(:proof_of_address)
    end

    it "returns :proof_of_address for bank_account_statement" do
      expect(described_class.for("bank_account_statement")).to eq(:proof_of_address)
    end

    it "accepts symbols as well as strings" do
      expect(described_class.for(:passport)).to eq(:identity)
    end

    it "returns nil for a document type with no category" do
      expect(described_class.for("certificate_of_incorporation")).to be_nil
    end
  end

  describe ".identity?" do
    it "is true for identity document types" do
      expect(described_class.identity?("passport")).to be true
    end

    it "is false for non-identity document types" do
      expect(described_class.identity?("utility_bill")).to be false
    end
  end

  describe ".proof_of_address?" do
    it "is true for proof-of-address document types" do
      expect(described_class.proof_of_address?("bank_account_statement")).to be true
    end

    it "is false for non-proof-of-address document types" do
      expect(described_class.proof_of_address?("passport")).to be false
    end
  end

  describe ".types_for" do
    it "returns all document types in a category" do
      expect(described_class.types_for(:identity)).to contain_exactly("passport", "driving_licence")
    end

    it "returns an empty array for an unknown category" do
      expect(described_class.types_for(:nonexistent)).to eq([])
    end
  end
end
