# frozen_string_literal: true

module Registry
  # Stand-in company registry for the fictional jurisdiction Utopia ("xu"),
  # UAT/dev only (MH-310). It lets registry-filled applicants be tested
  # repeatably without a real Companies House company, and is only resolvable
  # when SYNTHETIC_DATA_ENABLED is on (see Registry::Lookup.client_class_for).
  #
  # The company number selects a scenario from config/synthetic/registry_scenarios.yml.
  # It returns the same FetchResult shape as Registry::CompaniesHouseUkClient
  # (shared examples keep the two in step) and never makes a network request.
  class SyntheticClient < Client
    SCENARIOS_PATH = Rails.root.join("config/synthetic/registry_scenarios.yml")

    def self.scenarios
      @scenarios ||= YAML.safe_load_file(SCENARIOS_PATH).freeze
    end

    # Excludes MH-312's error entries — those aren't a company profile to run
    # the shared success-result examples against.
    def self.scenario_numbers
      scenarios.reject { |_, data| data["error"] }.keys
    end

    def fetch(company_number:)
      number = company_number.to_s.strip.upcase
      scenario = self.class.scenarios[number]
      return FetchResult.failure(error_type: :not_found) if scenario.nil?
      # MH-312: a deterministic error-path number (e.g. XU000401 -> unauthorized)
      # — never reported to Honeybadger, unlike the real client's own failures,
      # since nothing here is an actual incident.
      return FetchResult.failure(error_type: scenario["error"].to_sym) if scenario["error"]

      FetchResult.success(
        company_name: scenario["company_name"],
        status: scenario["status"],
        incorporated_on: Date.iso8601(scenario["incorporated_on"]),
        directors: map_directors(scenario["officers"]),
        addresses: [ map_address(scenario["address"]) ],
        # MH-313: "pscs" is optional — most scenarios have none.
        people_with_significant_control: map_pscs(scenario["pscs"] || []),
        raw_response: raw_response(number, scenario)
      )
    end

    private

    def map_directors(officers)
      officers.map do |officer|
        dob = officer["date_of_birth"] || {}

        {
          name: officer["name"],
          role: officer["role"],
          appointed_on: parse_date(officer["appointed_on"]),
          resigned_on: parse_date(officer["resigned_on"]),
          # MH-303: mirrors Registry::CompaniesHouseUkClient#map_directors.
          date_of_birth_month: dob["month"],
          date_of_birth_year: dob["year"]
        }
      end
    end

    # MH-313: mirrors Registry::CompaniesHouseUkClient#map_pscs.
    def map_pscs(pscs)
      pscs.map do |psc|
        dob = psc["date_of_birth"] || {}
        address = psc["address"] || {}

        {
          name: psc["name"],
          kind: psc["kind"],
          natures_of_control: Array(psc["natures_of_control"]),
          notified_on: parse_date(psc["notified_on"]),
          ceased_on: parse_date(psc["ceased_on"]),
          nationality: psc["nationality"],
          date_of_birth_month: dob["month"],
          date_of_birth_year: dob["year"],
          line1: address["line1"],
          city: address["city"],
          postcode: address["postcode"],
          # MH-313: for a corporate PSC, "country" is where it's registered
          # (not the correspondence address) — the field Kyc::OwnershipFromRegistry
          # checks against Kyc::NomineeDetector::NOMINEE_JURISDICTIONS.
          country: psc["country"] || address["country"],
          registration_number: psc["registration_number"]
        }
      end
    end

    def map_address(address)
      {
        kind: "registered",
        line1: address["line1"],
        city: address["city"],
        postcode: address["postcode"],
        country: address["country"]
      }
    end

    # Keyed and shaped like the Companies House responses the real client stores.
    def raw_response(number, scenario)
      address = scenario["address"]
      {
        "company" => {
          "company_name" => scenario["company_name"],
          "company_number" => number,
          "company_status" => scenario["status"],
          "date_of_creation" => scenario["incorporated_on"],
          "registered_office_address" => {
            "address_line_1" => address["line1"],
            "locality" => address["city"],
            "postal_code" => address["postcode"],
            "country" => address["country"]
          }
        },
        "officers" => { "items" => scenario["officers"].map { |officer| raw_officer(officer) } },
        "persons_with_significant_control" => { "items" => (scenario["pscs"] || []).map { |psc| raw_psc(psc) } }
      }
    end

    def raw_officer(officer)
      raw = {
        "name" => officer["name"],
        "officer_role" => officer["role"],
        "appointed_on" => officer["appointed_on"],
        "resigned_on" => officer["resigned_on"]
      }
      raw["date_of_birth"] = officer["date_of_birth"] if officer["date_of_birth"]
      raw
    end

    def raw_psc(psc)
      raw = {
        "name" => psc["name"],
        "kind" => psc["kind"],
        "natures_of_control" => Array(psc["natures_of_control"]),
        "notified_on" => psc["notified_on"],
        "ceased_on" => psc["ceased_on"],
        "nationality" => psc["nationality"],
        "address" => (psc["address"] || {}).merge("country" => psc["country"] || psc.dig("address", "country")),
        "identification" => { "registration_number" => psc["registration_number"] }
      }
      raw["date_of_birth"] = psc["date_of_birth"] if psc["date_of_birth"]
      raw
    end

    def parse_date(value)
      value.present? ? Date.iso8601(value) : nil
    end
  end
end
