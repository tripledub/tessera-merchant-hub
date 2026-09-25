# frozen_string_literal: true

module Kyc
  class OwnershipFromRegistry
    UBO_THRESHOLD = 25.0
    NUMERIC_BAND = /\A(?:ownership-of-shares|voting-rights)-(\d+)-to-(\d+)-percent/
    # MH-313: the registry-side counterpart of Kyc::NomineeDetector's own
    # jurisdiction check — reuses its list rather than duplicating it, so the
    # two can never drift apart.
    NOMINEE_JURISDICTIONS = Kyc::NomineeDetector::NOMINEE_JURISDICTIONS
    PERCENTAGE_TOLERANCE = Kyc::OwnershipPercentageValidator::TOLERANCE

    def self.call(registry_profile)
      new(registry_profile).call
    end

    def initialize(registry_profile)
      @profile = registry_profile
      @applicant = registry_profile.applicant
    end

    def call
      reset_existing_registry_ubo_warnings
      reset_existing_registry_nominee_warnings
      reset_existing_registry_percentage_warnings

      active_pscs = @profile.people_with_significant_control.where(ceased_on: nil)
      active_pscs.find_each do |psc|
        flag_ubo(psc)
        flag_nominee_jurisdiction(psc)
      end
      flag_percentage_deviation(active_pscs)
    end

    private

    # Registry-derived UBO warnings are identified by having no corporate_entity —
    # document-extracted ones (via Kyc::EffectiveUboCalculator) always have one.
    def reset_existing_registry_ubo_warnings
      Kyc::ValidationWarning.where(
        applicant: @applicant, warning_type: :ubo_threshold_exceeded, corporate_entity_id: nil
      ).delete_all
    end

    # MH-313: registry-derived nominee/percentage warnings are identified the
    # same way — no corporate_entity, unlike Kyc::NomineeDetector/
    # Kyc::OwnershipPercentageValidator's document-extracted ones.
    def reset_existing_registry_nominee_warnings
      Kyc::ValidationWarning.where(
        applicant: @applicant, warning_type: :nominee_detected, corporate_entity_id: nil
      ).delete_all
    end

    def reset_existing_registry_percentage_warnings
      Kyc::ValidationWarning.where(
        applicant: @applicant, warning_type: :percentage_deviation, corporate_entity_id: nil
      ).delete_all
    end

    # MH-313: Kyc::NomineeDetector only ever looks at document-extracted
    # Kyc::CorporateEntity rows, never a registry-fetched PSC directly — this
    # is the registry-side equivalent, raising the same warning type for a
    # corporate PSC registered in a known nominee jurisdiction.
    def flag_nominee_jurisdiction(psc)
      return unless corporate?(psc)
      return unless NOMINEE_JURISDICTIONS.include?(psc.country)

      Kyc::ValidationWarning.create!(
        applicant: @applicant,
        warning_type: :nominee_detected,
        message: "Nominee detected: #{psc.name} — registered in #{psc.country}",
        metadata: { detection_reason: "nominee_jurisdiction", jurisdiction: psc.country }
      )
    end

    # MH-313: the registry-side equivalent of Kyc::OwnershipPercentageValidator
    # — but only for an overshoot (sum of PSCs' own lower-bound percentages
    # already exceeds 100%, a plain logical impossibility). Never flags an
    # undershoot: percentage_for is each PSC's lower bound (Companies House
    # bands, not exact percentages), so a single majority owner already sums
    # short of 100 by design, and shareholders below the 25% PSC-reporting
    # threshold are never listed at all — both are normal, not a deviation.
    def flag_percentage_deviation(active_pscs)
      percentages = active_pscs.filter_map { |psc| percentage_for(psc) }
      return if percentages.empty?

      total = percentages.sum.to_f
      overshoot = total - 100.0
      return if overshoot <= PERCENTAGE_TOLERANCE

      company_name = @applicant.company_name.presence || @applicant.name
      Kyc::ValidationWarning.create!(
        applicant: @applicant,
        warning_type: :percentage_deviation,
        message: "Ownership of #{company_name} sums to at least #{total}% (expected 100%) — Companies House PSC register",
        metadata: { expected: 100.0, actual: total, deviation: overshoot }
      )
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
