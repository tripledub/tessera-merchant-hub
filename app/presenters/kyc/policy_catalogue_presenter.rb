# frozen_string_literal: true

module Kyc
  class PolicyCataloguePresenter < BasePresenter
    Sector = Data.define(:key, :label, :shared_requirements, :sector_requirements)
    Requirement = Data.define(
      :title, :guidance, :outcome, :outcome_badge_class, :source, :document_type, :summary, :details
    )

    presents :registry

    def sectors
      @sectors ||= Applicant.sectors.keys.map { |sector| present_sector(sector) }
    end

    private

    def present_sector(sector)
      requirements = registry.requirements_for(sector)
      shared, specific = requirements.partition { |requirement| shared_requirement_ids.include?(requirement.id) }

      Sector.new(
        key: sector,
        label: I18n.t("applicants.sectors.#{sector}"),
        shared_requirements: shared.map { |requirement| present_requirement(requirement) },
        sector_requirements: specific.map { |requirement| present_requirement(requirement) }
      )
    end

    # The general sector has no overlay: its effective policy is the shared
    # base policy. Comparing stable requirement IDs lets this presentation
    # distinguish inherited requirements without parsing the YAML again.
    def shared_requirement_ids
      @shared_requirement_ids ||= registry.requirements_for("general").map(&:id).to_set
    end

    def present_requirement(requirement)
      parameters = requirement.parameters
      document_type = KycDocument.document_type_label(parameters.fetch("document_type"))

      Requirement.new(
        title: requirement.title,
        guidance: requirement.guidance,
        outcome: I18n.t("kyc.policies.index.outcomes.#{requirement.outcome}"),
        outcome_badge_class: requirement.outcome == "blocking" ? "badge-error" : "badge-warning",
        source: requirement.source,
        document_type: document_type,
        summary: requirement_summary(requirement, document_type),
        details: requirement_details(requirement)
      )
    end

    def requirement_summary(requirement, document_type)
      I18n.t("kyc.policies.index.rules.#{requirement.rule}.summary", document: document_type)
    end

    def requirement_details(requirement)
      return [] unless requirement.rule == "document_validity"

      parameters = requirement.parameters
      details = [
        I18n.t("kyc.policies.index.details.mode",
               value: I18n.t("kyc.policies.index.validity_modes.#{parameters.fetch('mode')}")),
        I18n.t("kyc.policies.index.details.version", value: parameters.fetch("version")),
        I18n.t("kyc.policies.index.details.effective_from",
               value: I18n.l(parameters.fetch("effective_from"), format: :long)),
        required_dates_text(parameters.fetch("required_dates"))
      ]

      details << warning_thresholds_text(parameters) if parameters.fetch("warning_thresholds").any?
      details << I18n.t("kyc.policies.index.details.maximum_age",
                        count: parameters.fetch("max_age_months")) if parameters["max_age_months"]
      details
    end

    def required_dates_text(required_dates)
      labels = required_dates.map { |date| I18n.t("kyc.policies.index.date_fields.#{date}") }
      I18n.t("kyc.policies.index.details.required_dates", count: labels.size, value: labels.to_sentence)
    end

    def warning_thresholds_text(parameters)
      thresholds = parameters.fetch("warning_thresholds").map(&:to_s).to_sentence
      key = parameters.fetch("mode") == "expires" ? "expiry_warnings" : "freshness_warnings"
      I18n.t("kyc.policies.index.details.#{key}", value: thresholds)
    end
  end
end
