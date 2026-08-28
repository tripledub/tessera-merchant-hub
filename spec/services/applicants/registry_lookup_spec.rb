# frozen_string_literal: true

require "rails_helper"

RSpec.describe Applicants::RegistryLookup do
  let(:fake_client_class) { Class.new(Registry::Client) }
  let(:fake_client) { instance_double(fake_client_class) }

  before do
    stub_const("Registry::Lookup::CLIENTS", { "gb" => fake_client_class })
    allow(fake_client_class).to receive(:new).and_return(fake_client)
  end

  describe ".call" do
    context "when the registry lookup succeeds" do
      let(:applicant) { create(:applicant, registry_jurisdiction: "gb", company_number: "12345678") }
      let(:fetch_result) do
        Registry::FetchResult.success(
          company_name: "Acme Ltd", status: "active", incorporated_on: Date.new(2020, 1, 1),
          directors: [ { name: "DOE, Jane", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil } ],
          addresses: [],
          people_with_significant_control: [
            {
              name: "Mr John Smith", kind: "individual-person-with-significant-control",
              natures_of_control: [ "ownership-of-shares-75-to-100-percent" ],
              notified_on: Date.new(2020, 1, 1), ceased_on: nil, nationality: "British",
              date_of_birth_month: 1, date_of_birth_year: 1980,
              line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil
            }
          ]
        )
      end

      before do
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "returns a success result wrapping the applicant" do
        result = described_class.call(applicant)

        expect(result.success).to be(true)
        expect(result.applicant).to eq(applicant)
      end

      it "persists the registry snapshot" do
        expect { described_class.call(applicant) }
          .to change { applicant.registry_profiles.count }.by(1)
      end

      it "updates the applicant's company_name from the registry profile" do
        described_class.call(applicant)

        expect(applicant.reload.company_name).to eq("Acme Ltd")
      end

      it "promotes active directors, but not PSCs, to kyc_principals" do
        expect { described_class.call(applicant) }
          .to change { applicant.kyc_principals.count }.by(1)

        expect(applicant.kyc_principals.pluck(:name)).to contain_exactly("DOE, Jane")
      end

      it "flags the PSC as a UBO without creating any corporate entities" do
        described_class.call(applicant)

        expect(applicant.corporate_entities).to be_empty
        expect(Kyc::ValidationWarning.where(applicant: applicant, warning_type: :ubo_threshold_exceeded).count).to eq(1)
      end

      it "does not create duplicate principals when retried again" do
        described_class.call(applicant)

        expect { described_class.call(applicant) }
          .not_to change { applicant.kyc_principals.count }
      end
    end

    context "when the registry lookup fails" do
      let(:applicant) { create(:applicant, registry_jurisdiction: "gb", company_number: "00000000") }
      let(:fetch_result) { Registry::FetchResult.failure(error_type: :unavailable) }

      before do
        allow(fake_client).to receive(:fetch).with(company_number: "00000000").and_return(fetch_result)
      end

      it "returns a failure result wrapping the applicant" do
        result = described_class.call(applicant)

        expect(result.success).to be(false)
        expect(result.applicant).to eq(applicant)
      end

      it "persists nothing" do
        expect { described_class.call(applicant) }
          .not_to change { applicant.registry_profiles.count }
      end
    end
  end
end
