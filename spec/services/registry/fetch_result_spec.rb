# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::FetchResult do
  describe ".success" do
    it "builds a successful result with no error fields" do
      result = described_class.success(
        company_name: "Acme Ltd",
        status: "active",
        incorporated_on: Date.new(2020, 1, 1),
        directors: [ { name: "Jane Doe", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil } ],
        addresses: [ { kind: "registered", line1: "10 Business Park", city: "Bristol", postcode: "BS1 1AA", country: "United Kingdom" } ]
      )

      expect(result.success).to be(true)
      expect(result.error_type).to be_nil
      expect(result.error_message).to be_nil
      expect(result.company_name).to eq("Acme Ltd")
      expect(result.directors).to eq([ { name: "Jane Doe", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil } ])
      expect(result.addresses).to eq([ { kind: "registered", line1: "10 Business Park", city: "Bristol", postcode: "BS1 1AA", country: "United Kingdom" } ])
    end
  end

  describe ".failure" do
    it "builds a failed result with no company data" do
      result = described_class.failure(error_type: :not_found, error_message: "no such company")

      expect(result.success).to be(false)
      expect(result.error_type).to eq(:not_found)
      expect(result.error_message).to eq("no such company")
      expect(result.company_name).to be_nil
      expect(result.directors).to eq([])
      expect(result.addresses).to eq([])
    end

    it "defaults error_message to nil" do
      result = described_class.failure(error_type: :unavailable)

      expect(result.error_message).to be_nil
    end
  end
end
