# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PrincipalPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:kyc_principal) { build(:kyc_principal) }
  let(:presenter) { described_class.new(kyc_principal, template) }

  describe "#address_lines" do
    it "returns an empty array when no address fields are present" do
      kyc_principal.assign_attributes(address_line1: nil, address_line2: nil, city: nil, postcode: nil, country: nil)
      expect(presenter.address_lines).to eq([])
    end

    it "builds line1, city/postcode, and country when address_line2 is blank" do
      kyc_principal.assign_attributes(
        address_line1: "42 Oak Avenue", address_line2: nil,
        city: "London", postcode: "SW1A 1AA", country: "United Kingdom"
      )

      expect(presenter.address_lines).to eq([ "42 Oak Avenue", "London, SW1A 1AA", "United Kingdom" ])
    end

    it "includes address_line2 when present" do
      kyc_principal.assign_attributes(
        address_line1: "42 Oak Avenue", address_line2: "Suite 3",
        city: "London", postcode: "SW1A 1AA", country: "United Kingdom"
      )

      expect(presenter.address_lines).to eq([ "42 Oak Avenue", "Suite 3", "London, SW1A 1AA", "United Kingdom" ])
    end

    it "still returns lines when only one field (e.g. city) is present" do
      kyc_principal.assign_attributes(address_line1: nil, address_line2: nil, city: "London", postcode: nil, country: nil)

      expect(presenter.address_lines).to eq([ nil, "London", nil ])
    end
  end
end
