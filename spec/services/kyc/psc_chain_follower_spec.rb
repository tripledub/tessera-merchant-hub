# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PscChainFollower do
  let(:applicant) { create(:applicant, company_number: "12345678", registry_jurisdiction: "gb", company_name: "Acme Ltd") }
  let(:registry_profile) { create(:registry_profile, applicant: applicant, company_number: "12345678") }

  def call(psc)
    described_class.call(psc)
  end

  describe ".call" do
    context "when the PSC is an individual, not corporate" do
      let(:psc) do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, kind: "individual-person-with-significant-control")
      end

      it "does nothing and returns a not_corporate failure" do
        result = call(psc)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_corporate)
        expect(Kyc::ValidationWarning.count).to eq(0)
      end
    end

    context "when the corporate PSC has no registration_number on file" do
      let(:psc) do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Mystery Holdings Ltd",
          kind: "corporate-entity-person-with-significant-control", registration_number: nil)
      end

      it "flags an unresolved_chain warning and returns invalid_number" do
        result = call(psc)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:invalid_number)

        warning = Kyc::ValidationWarning.last
        expect(warning.warning_type).to eq("unresolved_chain")
        expect(warning.message).to include("Mystery Holdings Ltd")
        expect(warning.typed_metadata.entity_name).to eq("Mystery Holdings Ltd")
      end
    end

    context "when the corporate PSC's registration_number is the applicant's own company (cycle)" do
      let(:psc) do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Acme Ltd",
          kind: "corporate-entity-person-with-significant-control", registration_number: "12345678")
      end

      it "flags an unresolved_chain warning and returns cycle_detected, without fetching" do
        allow(Registry::CompaniesHouseUkClient).to receive(:new)

        result = call(psc)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:cycle_detected)
        expect(Kyc::ValidationWarning.last.warning_type).to eq("unresolved_chain")
        expect(Registry::CompaniesHouseUkClient).not_to have_received(:new)
      end
    end

    context "when the corporate PSC's own registry fetch fails" do
      let(:psc) do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Intermediate Holdings Ltd",
          kind: "corporate-entity-person-with-significant-control", registration_number: "99999999")
      end
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }

      before do
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "99999999")
          .and_return(Registry::FetchResult.failure(error_type: :not_found))
      end

      it "flags an unresolved_chain warning and returns the failure error_type" do
        result = call(psc)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_found)
        expect(Kyc::ValidationWarning.last.warning_type).to eq("unresolved_chain")
      end
    end

    context "when the corporate PSC's own registry fetch succeeds" do
      let(:psc) do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Intermediate Holdings Ltd",
          kind: "corporate-entity-person-with-significant-control", registration_number: "99999999",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ])
      end
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }

      before { allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client) }

      def stub_fetch(pscs: [])
        allow(fake_client).to receive(:fetch).with(company_number: "99999999").and_return(
          Registry::FetchResult.success(
            company_name: "Intermediate Holdings Ltd", status: "active", incorporated_on: Date.new(2018, 1, 1),
            directors: [], addresses: [], people_with_significant_control: pscs
          )
        )
      end

      it "persists a new Registry::Profile under the same applicant" do
        psc
        stub_fetch

        expect { call(psc) }.to change { applicant.registry_profiles.count }.by(1)

        profile = applicant.registry_profiles.find_by(company_number: "99999999")
        expect(profile.company_name).to eq("Intermediate Holdings Ltd")
      end

      it "reuses an already-cached profile for that company_number instead of re-fetching" do
        create(:registry_profile, applicant: applicant, company_number: "99999999", company_name: "Cached Ltd")
        allow(fake_client).to receive(:fetch)

        call(psc)

        expect(fake_client).not_to have_received(:fetch)
      end

      it "returns a success result wrapping the fetched profile" do
        stub_fetch

        result = call(psc)

        expect(result.success).to be(true)
        expect(result.registry_profile.company_name).to eq("Intermediate Holdings Ltd")
      end

      it "flags unresolved_chain for a further corporate sub-PSC rather than fetching further (depth limit)" do
        stub_fetch(pscs: [
          { name: "Grandparent Corp", kind: "corporate-entity-person-with-significant-control",
            natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], notified_on: Date.new(2015, 1, 1),
            ceased_on: nil, nationality: nil, date_of_birth_month: nil, date_of_birth_year: nil,
            line1: nil, city: nil, postcode: nil, country: nil, registration_number: "55555555" }
        ])

        call(psc)

        warning = Kyc::ValidationWarning.find_by(warning_type: :unresolved_chain)
        expect(warning.message).to include("Grandparent Corp")
        expect(Registry::CompaniesHouseUkClient).to have_received(:new).once
      end

      it "flags an indirect ubo_threshold_exceeded warning when compounded ownership clears 25%" do
        stub_fetch(pscs: [
          { name: "Jane Doe", kind: "individual-person-with-significant-control",
            natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], notified_on: Date.new(2015, 1, 1),
            ceased_on: nil, nationality: "British", date_of_birth_month: 1, date_of_birth_year: 1980,
            line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil }
        ])

        call(psc)

        warning = Kyc::ValidationWarning.find_by(warning_type: :ubo_threshold_exceeded, corporate_entity_id: nil)
        expect(warning).to be_present
        expect(warning.message).to include("Jane Doe")
        expect(warning.message).to include("Intermediate Holdings Ltd")
        expect(warning.typed_metadata.effective_percentage).to eq(56.25) # 75% of 75%
        expect(warning.typed_metadata.threshold).to eq(25.0)
      end

      it "flags unresolved_chain for manual verification when compounded ownership does not clear 25%" do
        # level1 (psc) band is 75-100%, level2 band is 25-50% => compounded lower bound 75*25/100 = 18.75, below 25
        stub_fetch(pscs: [
          { name: "Small Fry", kind: "individual-person-with-significant-control",
            natures_of_control: [ "ownership-of-shares-25-to-50-percent" ], notified_on: Date.new(2015, 1, 1),
            ceased_on: nil, nationality: "British", date_of_birth_month: 1, date_of_birth_year: 1980,
            line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil }
        ])

        call(psc)

        expect(Kyc::ValidationWarning.where(warning_type: :ubo_threshold_exceeded)).to be_empty
        warning = Kyc::ValidationWarning.find_by(warning_type: :unresolved_chain)
        expect(warning.message).to include("Small Fry")
      end

      it "flags unresolved_chain when neither level has a numeric control band to compound" do
        stub_fetch(pscs: [
          { name: "Control Only", kind: "individual-person-with-significant-control",
            natures_of_control: [ "significant-influence-or-control" ], notified_on: Date.new(2015, 1, 1),
            ceased_on: nil, nationality: "British", date_of_birth_month: 1, date_of_birth_year: 1980,
            line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil }
        ])

        call(psc)

        expect(Kyc::ValidationWarning.where(warning_type: :ubo_threshold_exceeded)).to be_empty
        expect(Kyc::ValidationWarning.find_by(warning_type: :unresolved_chain).message).to include("Control Only")
      end

      it "does not process a ceased sub-PSC" do
        stub_fetch(pscs: [
          { name: "Gone Now", kind: "individual-person-with-significant-control",
            natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], notified_on: Date.new(2015, 1, 1),
            ceased_on: Date.new(2020, 1, 1), nationality: "British", date_of_birth_month: 1, date_of_birth_year: 1980,
            line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil }
        ])

        call(psc)

        expect(Kyc::ValidationWarning.count).to eq(0)
      end
    end
  end
end
