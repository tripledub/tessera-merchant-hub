# frozen_string_literal: true

module Kyc
  class PolicyValiditySync
    class Conflict < StandardError; end

    IMMUTABLE_ATTRIBUTES = %i[
      document_type version effective_from mode required_dates warning_thresholds max_age_months blocking
    ].freeze

    class << self
      def call(registry: Kyc::PolicyRegistry.instance)
        new(registry: registry).call
      end
    end

    def initialize(registry:)
      @registry = registry
    end

    def call
      result = { created: 0, unchanged: 0 }

      validity_requirements.each do |requirement|
        outcome = synchronize(requirement.parameters)
        result[outcome] += 1
      end

      result
    end

    private

    attr_reader :registry

    def validity_requirements
      Applicant.sectors.keys
        .flat_map { |sector| registry.requirements_for(sector) }
        .uniq(&:id)
        .select { |requirement| requirement.rule == "document_validity" }
    end

    def synchronize(parameters)
      attributes = policy_attributes(parameters)

      Kyc::DocumentValidityPolicy.transaction do
        acquire_advisory_lock(attributes.fetch(:document_type), attributes.fetch(:version))
        policy = Kyc::DocumentValidityPolicy.find_by(
          document_type: attributes.fetch(:document_type),
          version: attributes.fetch(:version)
        )

        if policy
          verify_immutable_content!(policy, attributes)
          :unchanged
        else
          Kyc::DocumentValidityPolicy.create!(attributes)
          :created
        end
      end
    end

    def policy_attributes(parameters)
      {
        document_type: parameters.fetch("document_type"),
        version: parameters.fetch("version"),
        effective_from: parameters.fetch("effective_from"),
        mode: parameters.fetch("mode"),
        required_dates: parameters.fetch("required_dates"),
        warning_thresholds: parameters.fetch("warning_thresholds"),
        max_age_months: parameters["max_age_months"],
        blocking: parameters.fetch("blocking")
      }
    end

    def acquire_advisory_lock(document_type, version)
      Kyc::DocumentValidityPolicy.connection.raw_connection.exec_params(
        "SELECT pg_advisory_xact_lock(hashtext($1), $2::integer)",
        [ document_type, version ]
      )
    end

    def verify_immutable_content!(policy, attributes)
      mismatches = IMMUTABLE_ATTRIBUTES.reject do |attribute|
        policy.public_send(attribute) == attributes.fetch(attribute)
      end
      return if mismatches.empty?

      raise Conflict,
        "deployed validity policy conflicts with document_type=#{policy.document_type.inspect}, " \
        "version #{policy.version}; differing immutable attributes: #{mismatches.join(', ')}"
    end
  end
end
