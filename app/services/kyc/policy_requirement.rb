# frozen_string_literal: true

module Kyc
  class PolicyRequirement
    # Runtime-derived keys need static discovery hints.
    # i18n-tasks-use I18n.t("kyc.policy_requirements.base.passport_validity.title")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.base.passport_validity.guidance")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.base.utility_bill_freshness.title")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.base.utility_bill_freshness.guidance")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.crypto.vasp_registration.title")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.crypto.vasp_registration.guidance")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.crypto.wallet_custody_infrastructure_attestation.title")
    # i18n-tasks-use I18n.t("kyc.policy_requirements.crypto.wallet_custody_infrastructure_attestation.guidance")

    attr_reader :id, :rule, :outcome, :source, :parameters

    def initialize(id:, rule:, outcome:, source:, parameters:)
      @id = id
      @rule = rule
      @outcome = outcome
      @source = source
      @parameters = parameters
      freeze
    end

    def title
      I18n.t(self.class.translation_key(id, :title))
    end

    def guidance
      I18n.t(self.class.translation_key(id, :guidance))
    end

    def self.translation_key(id, attribute)
      "kyc.policy_requirements.#{id}.#{attribute}"
    end
  end
end
