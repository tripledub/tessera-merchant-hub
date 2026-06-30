# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionData::Concerns::AddressProviding do
  let(:dummy_class) do
    Class.new(ExtractionData::Base) { include ExtractionData::Concerns::AddressProviding }
  end

  describe "#to_matcher_hash" do
    it "raises NotImplementedError if the including class doesn't override person_full_name" do
      expect { dummy_class.new.to_matcher_hash }.to raise_error(NotImplementedError)
    end
  end

  describe "ExtractionData::UtilityBill" do
    it "maps full_name to person_full_name" do
      data = ExtractionData::UtilityBill.new(full_name: "Jane Smith")
      expect(data.person_full_name).to eq("Jane Smith")
    end

    it "exposes a structured address" do
      data = ExtractionData::UtilityBill.new(
        full_name: "Jane Smith",
        account_holder_address_line1: "12 High Street",
        account_holder_city: "London",
        account_holder_postcode: "SW1A 1AA",
        account_holder_country: "United Kingdom"
      )
      expect(data.structured_address).to eq(
        line1: "12 High Street", city: "London", postcode: "SW1A 1AA", country: "United Kingdom"
      )
    end

    it "builds a matcher hash with no date_of_birth" do
      data = ExtractionData::UtilityBill.new(full_name: "Jane Smith")
      expect(data.to_matcher_hash).to eq("full_name" => "Jane Smith", "date_of_birth" => nil)
    end
  end

  describe "ExtractionData::BankAccountStatement" do
    it "maps account_holder to person_full_name" do
      data = ExtractionData::BankAccountStatement.new(account_holder: "Pieter Bakker", bank_name: "ING")
      expect(data.person_full_name).to eq("Pieter Bakker")
    end

    it "exposes a structured address from the new address fields" do
      data = ExtractionData::BankAccountStatement.new(
        account_holder: "Pieter Bakker",
        bank_name: "ING",
        account_holder_address_line1: "Willem Augustinstraat 190",
        account_holder_city: "Amsterdam",
        account_holder_postcode: "1061 MJ",
        account_holder_country: "Netherlands"
      )
      expect(data.structured_address).to eq(
        line1: "Willem Augustinstraat 190", city: "Amsterdam", postcode: "1061 MJ", country: "Netherlands"
      )
    end

    it "builds a matcher hash using account_holder as the name" do
      data = ExtractionData::BankAccountStatement.new(account_holder: "Pieter Bakker", bank_name: "ING")
      expect(data.to_matcher_hash).to eq("full_name" => "Pieter Bakker", "date_of_birth" => nil)
    end
  end
end
