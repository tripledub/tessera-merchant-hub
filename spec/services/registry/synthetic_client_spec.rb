# frozen_string_literal: true

require "rails_helper"

# MH-310: the Utopia (xu) registry used to test registry-filled applicants
# without a real Companies House company. The company number picks the scenario.
RSpec.describe Registry::SyntheticClient do
  subject(:client) { described_class.new }

  describe ".scenario_numbers" do
    it "lists every non-error scenario" do
      expect(described_class.scenario_numbers).to eq(
        %w[XU000001 XU000002 XU000003 XU000010 XU000004 XU000005 XU000006]
      )
    end

    it "excludes MH-312's error-path numbers" do
      expect(described_class.scenario_numbers).not_to include("XU000401", "XU000429", "XU000503")
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

      it "records each officer's month and year of birth in the raw response, as Companies House does for PSCs" do
        officers = result.raw_response.dig("officers", "items")

        expect(officers.map { |o| [ o["name"], o["date_of_birth"] ] }).to contain_exactly(
          [ "TESTPERSON, Alex", { "month" => 3, "year" => 1980 } ],
          [ "EXAMPLESON, Morgan Lee", { "month" => 11, "year" => 1991 } ]
        )
      end

      it "maps each officer's month and year of birth onto the director (MH-303)" do
        expect(result.directors).to contain_exactly(
          hash_including(name: "TESTPERSON, Alex", date_of_birth_month: 3, date_of_birth_year: 1980),
          hash_including(name: "EXAMPLESON, Morgan Lee", date_of_birth_month: 11, date_of_birth_year: 1991)
        )
      end
    end

    # MH-313
    context "with XU000003 (corporate PSC chain)" do
      let(:result) { client.fetch(company_number: "XU000003") }

      it "has a corporate PSC pointing at XU000010's registration number" do
        expect(result.people_with_significant_control).to contain_exactly(
          hash_including(
            name: "Utopia Intermediate Holdings Ltd",
            kind: "corporate-entity-person-with-significant-control",
            registration_number: "XU000010"
          )
        )
      end
    end

    context "with XU000004 (nominee)" do
      let(:result) { client.fetch(company_number: "XU000004") }

      it "has a corporate PSC registered in Cyprus" do
        expect(result.people_with_significant_control).to contain_exactly(
          hash_including(name: "Cyprus Nominee Holdings Ltd", country: "CY")
        )
      end
    end

    context "with XU000005 (resigned director)" do
      let(:result) { client.fetch(company_number: "XU000005") }

      it "has one active and one resigned director" do
        expect(result.directors).to contain_exactly(
          hash_including(name: "ACTIVE, Morgan", resigned_on: nil),
          hash_including(name: "RESIGNED, Taylor", resigned_on: Date.new(2020, 6, 1))
        )
      end
    end

    context "with XU000006 (ownership overshoot)" do
      let(:result) { client.fetch(company_number: "XU000006") }

      it "has two PSCs whose lower-bound percentages sum past 100%" do
        expect(result.people_with_significant_control.size).to eq(2)
        expect(result.people_with_significant_control.map { |p| p[:natures_of_control] }).to contain_exactly(
          [ "ownership-of-shares-50-to-75-percent" ], [ "ownership-of-shares-75-to-100-percent" ]
        )
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

    # MH-312: deterministic error-path numbers, one per Registry::FetchResult
    # failure type Registry::CompaniesHouseUkClient can produce.
    {
      "XU000404" => :not_found,
      "XU000401" => :unauthorized,
      "XU000429" => :rate_limited,
      "XU000503" => :unavailable
    }.each do |number, error_type|
      it "returns #{error_type} for #{number}" do
        result = client.fetch(company_number: number)

        expect(result.success).to be(false)
        expect(result.error_type).to eq(error_type)
      end

      it "never notifies Honeybadger for #{number}, unlike the real client's own failures" do
        allow(Honeybadger).to receive(:notify)

        client.fetch(company_number: number)

        expect(Honeybadger).not_to have_received(:notify)
      end
    end
  end

  it "is a Registry::Client" do
    expect(client).to be_a(Registry::Client)
  end
end
