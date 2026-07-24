# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PrincipalPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:kyc_principal) { build(:kyc_principal) }
  let(:presenter) { described_class.new(kyc_principal, template) }

  describe "#address_present?" do
    it "returns false when no address fields are present" do
      kyc_principal.assign_attributes(address_line1: nil, city: nil, postcode: nil, country: nil)
      expect(presenter.address_present?).to be false
    end

    it "returns true when at least one address field is present" do
      kyc_principal.assign_attributes(address_line1: nil, city: "London", postcode: nil, country: nil)
      expect(presenter.address_present?).to be true
    end
  end

  describe "#city_postcode" do
    it "joins city and postcode with a comma" do
      kyc_principal.assign_attributes(city: "London", postcode: "SW1A 1AA")
      expect(presenter.city_postcode).to eq("London, SW1A 1AA")
    end

    it "omits a blank city" do
      kyc_principal.assign_attributes(city: nil, postcode: "SW1A 1AA")
      expect(presenter.city_postcode).to eq("SW1A 1AA")
    end

    it "returns an empty string when both are blank" do
      kyc_principal.assign_attributes(city: nil, postcode: nil)
      expect(presenter.city_postcode).to eq("")
    end
  end

  describe "delegated attributes" do
    it "delegates address_line1, address_line2, and country to the principal" do
      kyc_principal.assign_attributes(address_line1: "42 Oak Avenue", address_line2: "Suite 3", country: "United Kingdom")

      expect(presenter.address_line1).to eq("42 Oak Avenue")
      expect(presenter.address_line2).to eq("Suite 3")
      expect(presenter.country).to eq("United Kingdom")
    end
  end
end
