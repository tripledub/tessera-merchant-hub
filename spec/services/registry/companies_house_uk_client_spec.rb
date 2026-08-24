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

  describe "#fetch" do
    context "when both requests succeed" do
      before do
        stub_company
        stub_officers
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
