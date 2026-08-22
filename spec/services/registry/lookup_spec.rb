# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Lookup do
  let(:fake_client_class) { Class.new(Registry::Client) }
  let(:fake_client) { instance_double(fake_client_class) }

  before do
    stub_const("Registry::Lookup::CLIENTS", { "gb" => fake_client_class })
    allow(fake_client_class).to receive(:new).and_return(fake_client)
  end

  def call(applicant)
    described_class.call(applicant: applicant)
  end

  describe ".call" do
    context "when company_number is blank" do
      let(:applicant) { create(:applicant, registry_jurisdiction: "gb", company_number: nil) }

      it "returns an invalid_number failure without calling any client" do
        result = call(applicant)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:invalid_number)
        expect(fake_client_class).not_to have_received(:new)
      end
    end

    context "when the jurisdiction has no registered client" do
      let(:applicant) { create(:applicant, registry_jurisdiction: "mt", company_number: "12345678") }

      it "returns a not_supported failure" do
        result = call(applicant)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_supported)
      end
    end

    context "when registry_jurisdiction is blank" do
      let(:applicant) { create(:applicant, registry_jurisdiction: nil, company_number: "12345678") }

      it "returns a not_supported failure" do
        result = call(applicant)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_supported)
      end
    end

    context "when the client fetch succeeds" do
      let(:applicant) { create(:applicant, registry_jurisdiction: "gb", company_number: "12345678") }
      let(:fetch_result) do
        Registry::FetchResult.success(
          company_name: "Acme Ltd",
          status: "active",
          incorporated_on: Date.new(2020, 1, 1),
          directors: [ { name: "Jane Doe", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil } ],
          addresses: [ { kind: "registered", line1: "10 Business Park", city: "Bristol", postcode: "BS1 1AA", country: "United Kingdom" } ]
        )
      end

      before do
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "calls the client with the applicant's company_number" do
        call(applicant)
        expect(fake_client).to have_received(:fetch).with(company_number: "12345678")
      end

      it "returns a success result wrapping the new profile" do
        result = call(applicant)

        expect(result.success).to be(true)
        expect(result.error_type).to be_nil
        expect(result.registry_profile).to be_a(Registry::Profile)
        expect(result.registry_profile.company_name).to eq("Acme Ltd")
      end

      it "persists a Registry::Profile on the applicant" do
        expect { call(applicant) }.to change { applicant.registry_profiles.count }.by(1)

        profile = applicant.registry_profiles.last
        expect(profile.jurisdiction).to eq("gb")
        expect(profile.company_number).to eq("12345678")
        expect(profile.company_name).to eq("Acme Ltd")
        expect(profile.status).to eq("active")
        expect(profile.incorporated_on).to eq(Date.new(2020, 1, 1))
      end

      it "persists the directors from the fetch result" do
        call(applicant)

        profile = applicant.registry_profiles.last
        expect(profile.directors.count).to eq(1)
        expect(profile.directors.first.name).to eq("Jane Doe")
        expect(profile.directors.first.role).to eq("director")
      end

      it "persists the addresses from the fetch result" do
        call(applicant)

        profile = applicant.registry_profiles.last
        expect(profile.addresses.count).to eq(1)
        expect(profile.addresses.first.kind).to eq("registered")
        expect(profile.addresses.first.line1).to eq("10 Business Park")
      end

      it "creates a new profile row on a second fetch rather than updating the first" do
        call(applicant)
        expect { call(applicant) }.to change { applicant.registry_profiles.count }.by(1)
      end
    end

    context "when the client fetch fails" do
      let(:applicant) { create(:applicant, registry_jurisdiction: "gb", company_number: "00000000") }
      let(:fetch_result) { Registry::FetchResult.failure(error_type: :not_found, error_message: "no such company") }

      before do
        allow(fake_client).to receive(:fetch).with(company_number: "00000000").and_return(fetch_result)
      end

      it "returns a failure result with the client's error_type and error_message" do
        result = call(applicant)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_found)
        expect(result.error_message).to eq("no such company")
        expect(result.registry_profile).to be_nil
      end

      it "persists nothing" do
        expect { call(applicant) }.not_to change { applicant.registry_profiles.count }
      end
    end

    %i[not_found unauthorized rate_limited unavailable].each do |error_type|
      context "when the client returns a #{error_type} error" do
        let(:applicant) { create(:applicant, registry_jurisdiction: "gb", company_number: "12345678") }
        let(:fetch_result) { Registry::FetchResult.failure(error_type: error_type) }

        before do
          allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
        end

        it "returns a failure result with that error_type and persists nothing" do
          result = nil
          expect { result = call(applicant) }.not_to change { applicant.registry_profiles.count }

          expect(result.success).to be(false)
          expect(result.error_type).to eq(error_type)
        end
      end
    end
  end
end
