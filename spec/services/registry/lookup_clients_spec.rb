# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Lookup do
  describe "CLIENTS" do
    it "registers Registry::CompaniesHouseUkClient for the gb jurisdiction" do
      expect(described_class::CLIENTS["gb"]).to eq(Registry::CompaniesHouseUkClient)
    end

    it "does not register the synthetic client (it is only resolvable behind the gate)" do
      expect(described_class::CLIENTS).not_to have_key("xu")
    end
  end

  # MH-310: Utopia (xu) resolves to the synthetic registry only when
  # SYNTHETIC_DATA_ENABLED is on; otherwise it is an unsupported jurisdiction.
  describe ".client_class_for" do
    it "always resolves gb to Companies House" do
      expect(described_class.client_class_for("gb")).to eq(Registry::CompaniesHouseUkClient)
    end

    it "resolves no client for a jurisdiction that has none" do
      expect(described_class.client_class_for("mt")).to be_nil
      expect(described_class.client_class_for(nil)).to be_nil
    end

    context "when synthetic data is disabled" do
      include_context "with synthetic data disabled"

      it "does not resolve xu" do
        expect(described_class.client_class_for("xu")).to be_nil
      end
    end

    context "when synthetic data is enabled" do
      include_context "with synthetic data enabled"

      it "resolves xu to the synthetic client" do
        expect(described_class.client_class_for("xu")).to eq(Registry::SyntheticClient)
      end
    end
  end

  describe ".selectable_jurisdictions" do
    context "when synthetic data is disabled" do
      include_context "with synthetic data disabled"

      it { expect(described_class.selectable_jurisdictions).to eq(%w[gb]) }
    end

    context "when synthetic data is enabled" do
      include_context "with synthetic data enabled"

      it { expect(described_class.selectable_jurisdictions).to eq(%w[gb xu]) }
    end
  end

  describe ".call for a Utopia applicant" do
    let(:applicant) { create(:applicant, registry_jurisdiction: "xu", company_number: "XU000001") }

    context "when synthetic data is disabled" do
      include_context "with synthetic data disabled"

      it "is not_supported" do
        result = described_class.call(applicant: build(:applicant, registry_jurisdiction: "xu", company_number: "XU000001"))

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_supported)
      end
    end

    context "when synthetic data is enabled" do
      include_context "with synthetic data enabled"

      it "persists a registry profile from the synthetic registry" do
        result = described_class.call(applicant: applicant)

        expect(result.success).to be(true)
        profile = result.registry_profile
        expect(profile.jurisdiction).to eq("xu")
        expect(profile.company_name).to eq("Utopia Sample Trading Ltd")
        expect(profile.directors.count).to eq(2)
      end
    end
  end
end
