# frozen_string_literal: true

require "rails_helper"

RSpec.describe ControlPlane::MerchantProvisioner, type: :model do
  describe ".create!" do
    it "delegates to a new instance" do
      result = described_class.create!(name: "Acme Corp")

      expect(result).to include("name" => "Acme Corp")
      expect(result["merchant_id"]).to start_with("merch_")
    end
  end

  describe "#create!" do
    subject(:provisioner) { described_class.new }

    it "creates a Merchant record" do
      expect {
        provisioner.create!(name: "Acme Corp")
      }.to change(Merchant, :count).by(1)
    end

    it "returns a hash with all provided attributes" do
      result = provisioner.create!(
        name: "Acme Corp",
        company_name: "Acme Corp Ltd",
        country: "GB"
      )

      expect(result).to include(
        "name" => "Acme Corp",
        "company_name" => "Acme Corp Ltd",
        "country" => "GB"
      )
      expect(result["merchant_id"]).to start_with("merch_")
    end

    it "generates a unique merchant_id prefixed with merch_" do
      result = provisioner.create!(name: "Acme")
      expect(result["merchant_id"]).to match(/\Amerch_[A-Za-z0-9_-]+\z/)
    end

    it "stores nil for optional attributes when omitted" do
      result = provisioner.create!(name: "Acme")

      expect(result["company_name"]).to be_nil
      expect(result["country"]).to be_nil
    end

    it "persists the record with the correct data" do
      result = provisioner.create!(name: "Acme", company_name: "Acme Ltd", country: "DE")
      merchant = Merchant.find_by(merchant_id: result["merchant_id"])

      expect(merchant).to be_present
      expect(merchant.name).to eq("Acme")
      expect(merchant.company_name).to eq("Acme Ltd")
      expect(merchant.country).to eq("DE")
    end

    it "raises when the name is blank" do
      expect {
        provisioner.create!(name: "")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
