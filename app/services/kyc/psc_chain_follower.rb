# frozen_string_literal: true

module Kyc
  # Spike: follows a single corporate PSC one level deeper (depth-capped at 2
  # total levels: the applicant's own direct PSCs, then that corporate PSC's
  # own PSCs). See MH-223 for the design this implements and its open edges.
  class PscChainFollower
    NUMERIC_BAND = /\A(?:ownership-of-shares|voting-rights)-(\d+)-to-(\d+)-percent/
    UBO_THRESHOLD = 25.0

    Result = Data.define(:success, :registry_profile, :error_type) do
      def self.success(registry_profile)
        new(success: true, registry_profile: registry_profile, error_type: nil)
      end

      def self.failure(error_type)
        new(success: false, registry_profile: nil, error_type: error_type)
      end
    end

    def self.call(psc)
      new(psc).call
    end

    def initialize(psc)
      @psc = psc
      @applicant = psc.registry_profile.applicant
    end

    def call
      return Result.failure(:not_corporate) unless corporate?(@psc)

      registration_number = @psc.registration_number
      if registration_number.blank?
        flag_unresolved(@psc.name, "no registration number on file — cannot trace further")
        return Result.failure(:invalid_number)
      end

      if registration_number == @applicant.company_number
        flag_unresolved(@psc.name, "traces back to the applicant's own company — cycle detected")
        return Result.failure(:cycle_detected)
      end

      lookup_result = fetch_or_use_cached(registration_number)
      unless lookup_result.success
        flag_unresolved(@psc.name, "could not fetch registry data (#{lookup_result.error_type})")
        return Result.failure(lookup_result.error_type)
      end

      profile = lookup_result.registry_profile
      process_sub_pscs(profile)
      Result.success(profile)
    end

    private

    def corporate?(psc)
      !psc.kind.start_with?("individual-")
    end

    def fetch_or_use_cached(registration_number)
      cached = @applicant.registry_profiles.find_by(company_number: registration_number, jurisdiction: "gb")
      return Registry::Lookup::Result.success(cached) if cached

      Registry::Lookup.call(applicant: @applicant, company_number: registration_number, jurisdiction: "gb")
    end

    def process_sub_pscs(profile)
      level1_percentage = percentage_for(@psc)

      profile.people_with_significant_control.where(ceased_on: nil).find_each do |sub_psc|
        if corporate?(sub_psc)
          flag_unresolved(sub_psc.name, "a further corporate owner of #{profile.company_name} — chain depth limit reached")
        else
          flag_indirect(sub_psc, profile, level1_percentage)
        end
      end
    end

    def flag_indirect(sub_psc, profile, level1_percentage)
      compounded = compound(level1_percentage, percentage_for(sub_psc))

      if compounded && compounded >= UBO_THRESHOLD
        company_name = @applicant.company_name.presence || @applicant.name
        Kyc::ValidationWarning.create!(
          applicant: @applicant,
          warning_type: :ubo_threshold_exceeded,
          message: "Indirect UBO identified via chain-following: #{sub_psc.name} has an estimated " \
                   "#{compounded}% effective ownership of #{company_name} (through #{profile.company_name}) — " \
                   "lower-bound estimate from Companies House control bands, verify exact figures",
          metadata: { individual_name: sub_psc.name, effective_percentage: compounded, threshold: UBO_THRESHOLD }
        )
      else
        flag_unresolved(
          sub_psc.name,
          "found via #{profile.company_name}; ownership percentage could not be confirmed against the " \
          "25% threshold — manual verification required"
        )
      end
    end

    def flag_unresolved(entity_name, reason)
      Kyc::ValidationWarning.create!(
        applicant: @applicant,
        warning_type: :unresolved_chain,
        message: "Unresolved ownership chain: #{entity_name} — #{reason}",
        metadata: { entity_name: entity_name }
      )
    end

    def percentage_for(psc)
      bands = Array(psc.natures_of_control).filter_map { |nature| nature[NUMERIC_BAND, 1]&.to_i }
      bands.max
    end

    def compound(level1, level2)
      return nil unless level1 && level2

      (level1 * level2 / 100.0).round(2)
    end
  end
end
