# frozen_string_literal: true

require "rails_helper"

# MH-310: the Utopia (xu) registry used to test registry-filled applicants
# without a real Companies House company. The company number picks the scenario.
RSpec.describe Registry::SyntheticClient do
  subject(:client) { described_class.new }

  describe ".scenario_numbers" do
    it "lists the initial scenarios" do
      expect(described_class.scenario_numbers).to eq(%w[XU000001 XU000002])
    end
  end

  described_class.scenario_numbers.each do |number|
    context "with scenario #{number}" do
      let(:result) { described_class.new.fetch(company_number: number) }

      it_behaves_like "a registry client success result"
    end
  end

  describe "#fetch" do
    context "with XU000001 (simple company)" do
      let(:result) { client.fetch(company_number: "XU000001") }

      it "returns a company with two active directors and one registered address" do
        expect(result.company_name).to eq("Utopia Sample Trading Ltd")
        expect(result.directors.size).to eq(2)
        expect(result.directors).to all(include(role: "director", resigned_on: nil))
        expect(result.addresses.size).to eq(1)
        expect(result.addresses.first).to include(kind: "registered", country: "Utopia")
      end

      it "has no people with significant control" do
        expect(result.people_with_significant_control).to be_empty
      end
    end

    context "with XU000002 (officers matching the synthetic specimen passports)" do
      let(:result) { client.fetch(company_number: "XU000002") }

      it "lists the officers in Companies House name format" do
        expect(result.directors.pluck(:name)).to contain_exactly("TESTPERSON, Alex", "EXAMPLESON, Morgan Lee")
      end

      it "records each officer's month and year of birth in the raw response only, as Companies House does for PSCs" do
        officers = result.raw_response.dig("officers", "items")

        expect(officers.map { |o| [ o["name"], o["date_of_birth"] ] }).to contain_exactly(
          [ "TESTPERSON, Alex", { "month" => 3, "year" => 1980 } ],
          [ "EXAMPLESON, Morgan Lee", { "month" => 11, "year" => 1991 } ]
        )
        expect(result.directors).to all(satisfy { |d| d.keys.exclude?(:date_of_birth) })
      end
    end

    it "matches the number case-insensitively and ignores surrounding whitespace" do
      result = client.fetch(company_number: " xu000002 ")

      expect(result.success).to be(true)
      expect(result.company_name).to eq("Utopia Specimen Holdings Ltd")
    end

    it "returns not_found for a number that is not a scenario, as Companies House does for a 404" do
      result = client.fetch(company_number: "XU999999")

      expect(result.success).to be(false)
      expect(result.error_type).to eq(:not_found)
    end

    it "returns not_found for a number in another jurisdiction's format" do
      expect(client.fetch(company_number: "12345678").error_type).to eq(:not_found)
    end

    it "never makes a network request" do
      client.fetch(company_number: "XU000001")

      expect(WebMock).not_to have_requested(:any, /.*/)
    end
  end

  it "is a Registry::Client" do
    expect(client).to be_a(Registry::Client)
  end
end
