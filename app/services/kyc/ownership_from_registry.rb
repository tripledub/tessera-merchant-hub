# frozen_string_literal: true

module Kyc
  class OwnershipFromRegistry
    UBO_THRESHOLD = 25.0
    NUMERIC_BAND = /\A(?:ownership-of-shares|voting-rights)-(\d+)-to-(\d+)-percent/

    def self.call(registry_profile)
      new(registry_profile).call
    end

    def initialize(registry_profile)
      @profile = registry_profile
      @applicant = registry_profile.applicant
    end

    def call
      reset_existing_registry_ubo_warnings

      @profile.people_with_significant_control.where(ceased_on: nil).find_each do |psc|
        flag_ubo(psc)
      end
    end

    private

    # Registry-derived UBO warnings are identified by having no corporate_entity —
    # document-extracted ones (via Kyc::EffectiveUboCalculator) always have one.
    def reset_existing_registry_ubo_warnings
      Kyc::ValidationWarning.where(
        applicant: @applicant, warning_type: :ubo_threshold_exceeded, corporate_entity_id: nil
      ).delete_all
    end

    def flag_ubo(psc)
      company_name = @applicant.company_name.presence || @applicant.name
      percentage = percentage_for(psc)
      psc_kind = corporate?(psc) ? "company" : "person"

      Kyc::ValidationWarning.create!(
        applicant: @applicant,
        warning_type: :ubo_threshold_exceeded,
        message: "UBO identified via Companies House PSC register: #{psc.name} is a " \
                 "#{psc_kind} with significant control of #{company_name}",
        metadata: {
          individual_name: psc.name,
          effective_percentage: percentage,
          threshold: UBO_THRESHOLD
        }
      )
    end

    def corporate?(psc)
      !psc.kind.start_with?("individual-")
    end

    def percentage_for(psc)
      bands = Array(psc.natures_of_control).filter_map { |nature| nature[NUMERIC_BAND, 1]&.to_i }
      bands.max
    end
  end
end
