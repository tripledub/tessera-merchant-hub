# frozen_string_literal: true

module Onboarding
  # MH-391: company details the chat already knows without asking.
  module CompanyDefaults
    STAGE_KEY = "company_info"

    module_function

    # When the PSP chose a registry jurisdiction, the country follows from it, so the
    # applicant is not asked. A country they have already given is left alone.
    def seed_country(session)
      country = Onboarding::Jurisdictions.country_for(session.applicant.registry_jurisdiction)
      return if country.blank?

      company_info = session.stage_data.fetch(STAGE_KEY, {})
      return if company_info["country_of_incorporation"].present?

      session.update!(stage_data: session.stage_data.merge(
        STAGE_KEY => company_info.merge("country_of_incorporation" => country)
      ))
    end
  end
end
