# frozen_string_literal: true

require "rails_helper"

RSpec.describe Synthetic::ScenarioCatalogue do
  after { described_class.reset! }

  describe ".all" do
    it "loads and validates every real scenario file without raising" do
      expect { described_class.all }.not_to raise_error
    end

    it "includes the committed two-directors-one-passport scenario" do
      scenario = described_class.all.find { |s| s.id == "two-directors-one-passport" }

      expect(scenario).to be_present
      expect(scenario.company_number).to eq("XU000002")
      expect(scenario.people.map(&:persona_slug)).to eq(%w[alex-testperson morgan-lee-exampleson])
      expect(scenario.qase_cases).to eq(%w[KYN-29])
    end

    it "fails fast on a malformed scenario file" do
      broken_path = described_class::DIR.join("_broken_fixture.yml")
      File.write(broken_path, YAML.dump("id" => "broken", "title" => "Broken"))

      begin
        described_class.reset!
        expect { described_class.all }.to raise_error(described_class::InvalidScenario, /company_number/)
      ensure
        FileUtils.rm_f(broken_path)
        described_class.reset!
      end
    end
  end

  describe ".find" do
    it "returns the matching scenario" do
      expect(described_class.find("two-directors-one-passport").title).to eq("Two directors, one uploaded passport")
    end

    it "raises RecordNotFound for an unknown id" do
      expect { described_class.find("nonexistent") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  # MH-311 AC1: a schema check so a malformed scenario fails fast.
  describe ".validate" do
    def validate(overrides = {})
      base = {
        "id" => "x", "title" => "X", "company_number" => "XU000001",
        "people" => [ { "persona" => "a", "role" => "director" } ],
        "ground_truth" => "...", "qase_cases" => [ "KYN-1" ]
      }
      described_class.send(:validate, base.merge(overrides), "fixture.yml")
    end

    it "passes a well-formed scenario" do
      expect(validate).to eq([])
    end

    %w[id title company_number ground_truth].each do |key|
      it "flags a missing #{key}" do
        data = { "id" => "x", "title" => "X", "company_number" => "XU000001",
                 "people" => [ { "persona" => "a", "role" => "director" } ],
                 "ground_truth" => "...", "qase_cases" => [ "KYN-1" ] }
        data.delete(key)

        errors = described_class.send(:validate, data, "fixture.yml")
        expect(errors.join).to include(key)
      end
    end

    it "flags an empty people array" do
      errors = validate("people" => [])
      expect(errors.join).to include("people")
    end

    it "flags a person missing a role" do
      errors = validate("people" => [ { "persona" => "a" } ])
      expect(errors.join).to include("role")
    end

    it "flags a document missing options" do
      errors = validate("people" => [ { "persona" => "a", "role" => "director",
                                        "documents" => [ { "type" => "passport" } ] } ])
      expect(errors.join).to include("options")
    end

    it "flags an empty qase_cases array" do
      errors = validate("qase_cases" => [])
      expect(errors.join).to include("qase_cases")
    end
  end

  # MH-311 AC3: for every scenario, the fake registry data (MH-310) and the
  # Synthetic::Persona records it references (MH-309) must agree on names
  # and dates of birth — otherwise a tester's registry-filled applicant and
  # uploaded documents would silently disagree with each other.
  describe "cross-consistency with the fake registry" do
    before { Synthetic::PersonaSeed.call }

    it "has a registry-fetched officer matching every scenario person's name" do
      described_class.all.each do |scenario|
        registry_scenario = Registry::SyntheticClient.scenarios.fetch(scenario.company_number)
        officer_names = registry_scenario["officers"].map { |o| Kyc::CompaniesHouseName.normalize(o["name"]).downcase }

        scenario.people.each do |person|
          persona = person.persona
          normalized = Kyc::CompaniesHouseName.normalize(persona.full_name).downcase

          expect(officer_names).to include(normalized),
            "expected #{scenario.id}'s registry officers #{officer_names.inspect} to include " \
              "persona #{persona.slug}'s name #{normalized.inspect}"
        end
      end
    end

    it "has a registry date of birth (month/year) matching every scenario person's persona, where the registry records one" do
      described_class.all.each do |scenario|
        registry_scenario = Registry::SyntheticClient.scenarios.fetch(scenario.company_number)

        scenario.people.each do |person|
          persona = person.persona
          normalized = Kyc::CompaniesHouseName.normalize(persona.full_name).downcase
          officer = registry_scenario["officers"].find do |o|
            Kyc::CompaniesHouseName.normalize(o["name"]).downcase == normalized
          end
          dob = officer["date_of_birth"]
          next unless dob

          expect(persona.date_of_birth.month).to eq(dob["month"])
          expect(persona.date_of_birth.year).to eq(dob["year"])
        end
      end
    end
  end
end
