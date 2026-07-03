# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionData::CertificateOfRegisteredAddress do
  subject(:schema) do
    described_class.new(
      "company_name" => "Acme Ltd",
      "line1" => "10 Business Park",
      "city" => "Bristol",
      "postcode" => "BS1 1AA",
      "country" => "United Kingdom",
      "issue_date" => "2025-01-15"
    )
  end

  it "exposes structured_address" do
    expect(schema.structured_address).to eq(
      line1: "10 Business Park",
      city: "Bristol",
      postcode: "BS1 1AA",
      country: "United Kingdom"
    )
  end

  it "is valid with required fields" do
    expect(schema).to be_valid
  end

  it "is invalid without company_name" do
    schema.company_name = nil
    expect(schema).not_to be_valid
  end
end
