# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PolicyCataloguePresenter, type: :presenter do
  subject(:presenter) { described_class.new(registry, template) }

  let(:template) { ApplicationController.new.view_context }
  let(:registry) { Kyc::PolicyRegistry.load! }

  describe "#sectors" do
    it "presents every applicant sector in enum order" do
      expect(presenter.sectors.map(&:key)).to eq(%w[
        general crypto_exchange gambling forex_brokerage proprietary_trading
      ])
    end

    it "separates shared requirements from the selected sector's requirements" do
      gambling = presenter.sectors.find { |sector| sector.key == "gambling" }

      expect(gambling.shared_requirements.map(&:title)).to eq([
        "Passport validity", "Utility bill freshness"
      ])
      expect(gambling.sector_requirements.map(&:title)).to include(
        "Gaming licence", "Responsible gambling policy"
      )
    end
  end

  describe "requirement presentation" do
    it "describes a required document without exposing registry parameters" do
      gambling = presenter.sectors.find { |sector| sector.key == "gambling" }
      licence = gambling.sector_requirements.find { |requirement| requirement.title == "Gaming licence" }

      expect(licence).to have_attributes(
        outcome: "Blocking",
        source: "2.1",
        document_type: "Gaming Licence",
        summary: "A current, non-superseded Gaming Licence document must be present for the applicant."
      )
    end

    it "describes expiry validity configuration in plain language" do
      general = presenter.sectors.find { |sector| sector.key == "general" }
      passport = general.shared_requirements.find { |requirement| requirement.title == "Passport validity" }

      expect(passport.details).to include(
        "Mode: Expiry",
        "Policy version: 2",
        "Effective from: August 21, 2026",
        "Required date: Expiry",
        "Warnings: 90 and 30 days before expiry"
      )
    end

    it "describes freshness configuration in plain language" do
      general = presenter.sectors.find { |sector| sector.key == "general" }
      utility_bill = general.shared_requirements.find do |requirement|
        requirement.title == "Utility bill freshness"
      end

      expect(utility_bill.details).to include(
        "Mode: Freshness",
        "Maximum age: 3 months",
        "Required date: Issued"
      )
    end
  end
end
