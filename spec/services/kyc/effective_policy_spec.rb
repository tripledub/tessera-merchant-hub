# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::EffectivePolicy do
  before do
    Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
  end

  describe ".for" do
    it "returns the immutable base policy for a general applicant" do
      applicant = build(:applicant, sector: :general)

      requirements = described_class.for(applicant)

      expect(requirements.map(&:id)).to eq(
        [ "base.passport_validity", "base.utility_bill_freshness" ]
      )
      expect(requirements).to be_frozen
    end

    it "composes the base and Crypto Exchange policies" do
      applicant = build(:applicant, sector: :crypto_exchange)

      requirements = described_class.for(applicant)

      expect(requirements.map(&:id)).to eq(
        [
          "base.passport_validity",
          "base.utility_bill_freshness",
          "crypto.vasp_registration",
          "crypto.wallet_custody_infrastructure_attestation"
        ]
      )
    end

    it "retains the version-2 passport expiry policy" do
      passport = described_class.for(build(:applicant)).find { |requirement| requirement.id == "base.passport_validity" }

      expect(passport.parameters).to eq(
        "document_type" => "passport",
        "version" => 2,
        "effective_from" => Date.new(2026, 8, 21),
        "mode" => "expires",
        "required_dates" => [ "expiry" ],
        "warning_thresholds" => [ 90, 30 ],
        "blocking" => true
      )
      expect(passport.source).to eq("MH-193")
    end

    it "retains the version-2 three-month utility-bill freshness policy" do
      utility_bill = described_class.for(build(:applicant)).find do |requirement|
        requirement.id == "base.utility_bill_freshness"
      end

      expect(utility_bill.parameters).to eq(
        "document_type" => "utility_bill",
        "version" => 2,
        "effective_from" => Date.new(2026, 8, 21),
        "mode" => "freshness",
        "required_dates" => [ "issued" ],
        "warning_thresholds" => [],
        "max_age_months" => 3,
        "blocking" => true
      )
      expect(utility_bill.source).to eq("MH-193")
    end

    it "defines only the two blocking Crypto Exchange document requirements" do
      crypto_requirements = described_class.for(build(:applicant, sector: :crypto_exchange)).drop(2)

      expect(crypto_requirements.map { |requirement| [ requirement.id, requirement.outcome, requirement.source ] }).to eq(
        [
          [ "crypto.vasp_registration", "blocking", "1.1" ],
          [ "crypto.wallet_custody_infrastructure_attestation", "blocking", "1.5" ]
        ]
      )
      expect(crypto_requirements.map(&:rule).uniq).to eq([ "required_document" ])
      expect(crypto_requirements.map { |requirement| requirement.parameters.fetch("document_type") }).to eq(
        [ "vasp_registration", "wallet_custody_infrastructure_attestation" ]
      )
    end
  end
end
