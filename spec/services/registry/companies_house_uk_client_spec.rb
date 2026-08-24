# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::CompaniesHouseUkClient do
  let(:base_url) { "https://companies-house.example.com" }
  let(:api_key) { "ch-api-key-123" }
  let(:client) { described_class.new(base_url: base_url, api_key: api_key) }
  let(:company_number) { "12345678" }
  let(:company_url) { "#{base_url}/company/#{company_number}" }
  let(:officers_url) { "#{base_url}/company/#{company_number}/officers" }
  let(:expected_auth_header) { "Basic #{Base64.strict_encode64("#{api_key}:")}" }

  let(:company_response) do
    {
      "company_name" => "Acme Ltd",
      "company_number" => company_number,
      "company_status" => "active",
      "date_of_creation" => "2020-01-01",
      "registered_office_address" => {
        "address_line_1" => "10 Business Park",
        "locality" => "Bristol",
        "postal_code" => "BS1 1AA",
        "country" => "United Kingdom"
      }
    }
  end

  let(:officers_response) do
    {
      "items" => [
        {
          "name" => "DOE, Jane",
          "officer_role" => "director",
          "appointed_on" => "2020-01-01",
          "resigned_on" => nil
        }
      ]
    }
  end

  let(:pscs_response) do
    {
      "items" => [
        {
          "name" => "Mr Albert Edward Short",
          "kind" => "individual-person-with-significant-control",
          "natures_of_control" => [ "ownership-of-shares-75-to-100-percent" ],
          "notified_on" => "2016-05-01",
          "nationality" => "British",
          "date_of_birth" => { "month" => 7, "year" => 1975 },
          "address" => {
            "address_line_1" => "10 Business Park",
            "locality" => "Bristol",
            "postal_code" => "BS1 1AA",
            "country" => "United Kingdom"
          },
          "ceased" => false
        },
        {
          "name" => "Ms Jane Doe",
          "kind" => "individual-person-with-significant-control",
          "natures_of_control" => [ "voting-rights-75-to-100-percent" ],
          "notified_on" => "2015-01-01",
          "ceased_on" => "2019-01-01",
          "nationality" => "British",
          "date_of_birth" => { "month" => 3, "year" => 1960 },
          "address" => {
            "address_line_1" => "10 Business Park",
            "locality" => "Bristol",
            "postal_code" => "BS1 1AA",
            "country" => "United Kingdom"
          },
          "ceased" => true
        }
      ]
    }
  end

  def stub_company(status: 200, body: company_response)
    stub_request(:get, company_url)
      .with(headers: { "Authorization" => expected_auth_header })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_officers(status: 200, body: officers_response)
    stub_request(:get, officers_url)
      .with(headers: { "Authorization" => expected_auth_header })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_pscs(status: 200, body: pscs_response)
    stub_request(:get, "#{base_url}/company/#{company_number}/persons-with-significant-control")
      .with(headers: { "Authorization" => expected_auth_header })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "#initialize" do
    it "defaults api_key to the companies_house Rails credential" do
      allow(Rails.application.credentials).to receive(:dig).with(:companies_house, :api_key).and_return("cred-key")

      stub_request(:get, "https://api.company-information.service.gov.uk/company/#{company_number}")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("cred-key:")}" })
        .to_return(status: 200, body: company_response.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.company-information.service.gov.uk/company/#{company_number}/officers")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("cred-key:")}" })
        .to_return(status: 200, body: officers_response.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.company-information.service.gov.uk/company/#{company_number}/persons-with-significant-control")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("cred-key:")}" })
        .to_return(status: 200, body: pscs_response.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new.fetch(company_number: company_number)

      expect(result.success).to be(true)
    end

    it "falls back to COMPANIES_HOUSE_API_KEY when no credential is set" do
      allow(Rails.application.credentials).to receive(:dig).with(:companies_house, :api_key).and_return(nil)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("COMPANIES_HOUSE_API_KEY").and_return("env-key")

      stub_request(:get, "https://api.company-information.service.gov.uk/company/#{company_number}")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("env-key:")}" })
        .to_return(status: 200, body: company_response.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.company-information.service.gov.uk/company/#{company_number}/officers")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("env-key:")}" })
        .to_return(status: 200, body: officers_response.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.company-information.service.gov.uk/company/#{company_number}/persons-with-significant-control")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("env-key:")}" })
        .to_return(status: 200, body: pscs_response.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new.fetch(company_number: company_number)

      expect(result.success).to be(true)
    end
  end

  describe "#fetch" do
    context "when all three requests succeed" do
      before do
        stub_company
        stub_officers
        stub_pscs
      end

      it "captures the raw company, officers, and PSC responses" do
        result = client.fetch(company_number: company_number)

        expect(result.raw_response).to eq(
          "company" => company_response,
          "officers" => officers_response,
          "persons_with_significant_control" => pscs_response
        )
      end

      it "returns a successful FetchResult mapped from both responses" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(true)
        expect(result.company_name).to eq("Acme Ltd")
        expect(result.status).to eq("active")
        expect(result.incorporated_on).to eq(Date.new(2020, 1, 1))
      end

      it "maps officers to directors" do
        result = client.fetch(company_number: company_number)

        expect(result.directors).to eq([
          { name: "DOE, Jane", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil }
        ])
      end

      it "maps the registered office address" do
        result = client.fetch(company_number: company_number)

        expect(result.addresses).to eq([
          { kind: "registered", line1: "10 Business Park", city: "Bristol", postcode: "BS1 1AA", country: "United Kingdom" }
        ])
      end

      it "authenticates with HTTP basic auth using the API key as username and a blank password" do
        client.fetch(company_number: company_number)
        expect(a_request(:get, company_url).with(headers: { "Authorization" => expected_auth_header })).to have_been_made
      end

      it "maps an active PSC with no ceased_on" do
        result = client.fetch(company_number: company_number)
        psc = result.people_with_significant_control.first

        expect(psc).to eq(
          name: "Mr Albert Edward Short",
          kind: "individual-person-with-significant-control",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ],
          notified_on: Date.new(2016, 5, 1),
          ceased_on: nil,
          nationality: "British",
          date_of_birth_month: 7,
          date_of_birth_year: 1975,
          line1: "10 Business Park",
          city: "Bristol",
          postcode: "BS1 1AA",
          country: "United Kingdom",
          registration_number: nil
        )
      end

      it "maps a ceased PSC with its ceased_on date" do
        result = client.fetch(company_number: company_number)
        psc = result.people_with_significant_control.second

        expect(psc).to eq(
          name: "Ms Jane Doe",
          kind: "individual-person-with-significant-control",
          natures_of_control: [ "voting-rights-75-to-100-percent" ],
          notified_on: Date.new(2015, 1, 1),
          ceased_on: Date.new(2019, 1, 1),
          nationality: "British",
          date_of_birth_month: 3,
          date_of_birth_year: 1960,
          line1: "10 Business Park",
          city: "Bristol",
          postcode: "BS1 1AA",
          country: "United Kingdom",
          registration_number: nil
        )
      end
    end

    context "when the company has no PSCs registered" do
      before do
        stub_company
        stub_officers
        stub_pscs(status: 404, body: { "errors" => [ { "error" => "psc-list-not-found" } ] })
      end

      it "still succeeds, with an empty people_with_significant_control list" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(true)
        expect(result.people_with_significant_control).to eq([])
      end
    end

    context "when a PSC is a corporate entity (no date_of_birth or nationality)" do
      before do
        stub_company
        stub_officers
        stub_pscs(body: {
          "items" => [
            {
              "name" => "Acme Holdings Ltd",
              "kind" => "corporate-entity-person-with-significant-control",
              "natures_of_control" => [ "ownership-of-shares-75-to-100-percent" ],
              "notified_on" => "2020-01-01",
              "identification" => {
                "registration_number" => "10925687",
                "country_registered" => "England"
              },
              "address" => {
                "address_line_1" => "10 Business Park",
                "locality" => "Bristol",
                "postal_code" => "BS1 1AA",
                "country" => "United Kingdom"
              },
              "ceased" => false
            }
          ]
        })
      end

      it "maps the corporate PSC with blank individual-only fields" do
        result = client.fetch(company_number: company_number)

        psc = result.people_with_significant_control.first
        expect(psc[:kind]).to eq("corporate-entity-person-with-significant-control")
        expect(psc[:nationality]).to be_nil
        expect(psc[:date_of_birth_month]).to be_nil
        expect(psc[:date_of_birth_year]).to be_nil
        expect(psc[:registration_number]).to eq("10925687")
      end
    end

    context "when the company is not found" do
      before { stub_company(status: 404, body: { "errors" => [ { "error" => "company-profile-not-found" } ] }) }

      it "returns a not_found failure" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:not_found)
      end
    end

    context "when the API key is rejected" do
      before { stub_company(status: 401, body: { "error" => "Invalid Authorization" }) }

      it "returns an unauthorized failure" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:unauthorized)
      end
    end

    context "when rate limited" do
      before { stub_company(status: 429, body: { "error" => "Too many requests" }) }

      it "returns a rate_limited failure" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:rate_limited)
      end
    end

    context "when the registry has a server error" do
      before { stub_company(status: 500, body: { "error" => "Internal Server Error" }) }

      it "returns an unavailable failure" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:unavailable)
      end
    end

    context "when the officers request fails after the company request succeeds" do
      before do
        stub_company
        stub_officers(status: 500, body: { "error" => "Internal Server Error" })
      end

      it "returns an unavailable failure" do
        result = client.fetch(company_number: company_number)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(:unavailable)
      end
    end
  end
end
