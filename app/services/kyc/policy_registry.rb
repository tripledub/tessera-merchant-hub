# frozen_string_literal: true

require "yaml"

module Kyc
  class PolicyRegistry
    class InvalidPolicy < StandardError; end

    SCHEMA_VERSION = 1
    BASE_SECTOR = "base"
    TOP_LEVEL_KEYS = %w[schema_version sector requirements].freeze
    REQUIREMENT_KEYS = %w[id rule outcome source parameters].freeze
    RULE_PARAMETERS = {
      "required_document" => %w[document_type subject],
      "document_validity" => %w[
        document_type version effective_from mode required_dates warning_thresholds max_age_months blocking
      ]
    }.freeze
    REQUIRED_RULE_PARAMETERS = {
      "required_document" => %w[document_type subject],
      "document_validity" => %w[
        document_type version effective_from mode required_dates warning_thresholds blocking
      ]
    }.freeze
    OUTCOMES = %w[blocking warning].freeze
    SUBJECTS = %w[applicant].freeze
    VALIDITY_MODES = %w[expires freshness].freeze

    class << self
      attr_accessor :instance

      def load!(path: Rails.root.join("config/kyc/policies"))
        new(path: path).tap(&:load!)
      end

      def requirements_for(sector)
        instance.requirements_for(sector)
      end

      def validity_applicable?(document_type)
        instance.validity_applicable?(document_type)
      end
    end

    def initialize(path:)
      @path = Pathname(path)
      @requirements_by_sector = {}
      @files_by_sector = {}
    end

    def load!
      @path.glob("*.yml").sort.each do |file|
        policy = safely_load(file)
        validate_policy!(policy, file)
        sector = policy.fetch("sector")

        if @requirements_by_sector.key?(sector)
          invalid!(file, "sector #{sector.inspect} is defined more than once")
        end

        seen_ids = {}
        @requirements_by_sector[sector] = policy.fetch("requirements").map do |attributes|
          validate_requirement!(attributes, file, seen_ids, sector)
          build_requirement(attributes)
        end.freeze
        @files_by_sector[sector] = file
      end

      validate_effective_compositions!
      @requirements_by_sector.freeze
      @files_by_sector.freeze
      freeze
    end

    def requirements_for(sector)
      validate_requested_sector!(sector)

      base = @requirements_by_sector.fetch(BASE_SECTOR, EMPTY_REQUIREMENTS)
      overlay = @requirements_by_sector.fetch(sector, EMPTY_REQUIREMENTS)
      (base + overlay).freeze
    end

    def validity_applicable?(document_type)
      @requirements_by_sector.fetch(BASE_SECTOR, EMPTY_REQUIREMENTS).any? do |requirement|
        requirement.rule == "document_validity" && requirement.parameters.fetch("document_type") == document_type
      end
    end

    private

    EMPTY_REQUIREMENTS = [].freeze

    def safely_load(file)
      YAML.safe_load_file(file, permitted_classes: [], permitted_symbols: [], aliases: false)
    rescue Psych::Exception => e
      invalid!(file, "could not be loaded as safe YAML: #{e.message}")
    end

    def validate_policy!(policy, file)
      invalid!(file, "top level must be a mapping") unless policy.is_a?(Hash)

      validate_keys!(policy, required: TOP_LEVEL_KEYS, allowed: TOP_LEVEL_KEYS, file: file)
      invalid!(file, "schema_version must be #{SCHEMA_VERSION}") unless policy["schema_version"] == SCHEMA_VERSION

      sectors = [ BASE_SECTOR, *Applicant.sectors.keys ]
      invalid!(file, "unsupported sector #{policy['sector'].inspect}") unless sectors.include?(policy["sector"])
      invalid!(file, "requirements must be an array") unless policy["requirements"].is_a?(Array)
    end

    def validate_requirement!(attributes, file, seen_ids, sector)
      invalid!(file, "each requirement must be a mapping") unless attributes.is_a?(Hash)

      id = attributes["id"]
      context = id.is_a?(String) && id.present? ? id : "unknown requirement"
      validate_keys!(attributes, required: REQUIREMENT_KEYS, allowed: REQUIREMENT_KEYS, file: file, context: context)
      validate_non_empty_strings!(attributes, file, context)

      rule = attributes.fetch("rule")
      invalid!(file, "unsupported rule #{rule.inspect}", context) unless RULE_PARAMETERS.key?(rule)
      if rule == "document_validity" && sector != BASE_SECTOR
        invalid!(file, "document_validity requirements must be declared in the base policy", context)
      end
      invalid!(file, "unsupported outcome #{attributes['outcome'].inspect}", context) unless OUTCOMES.include?(attributes["outcome"])
      if rule == "document_validity" && attributes["outcome"] != "blocking"
        invalid!(file, "document_validity outcome must be blocking", context)
      end
      invalid!(file, "parameters must be a mapping", context) unless attributes["parameters"].is_a?(Hash)

      validate_parameters!(rule, attributes.fetch("parameters"), file, context)

      if seen_ids.key?(id)
        invalid!(file, "duplicate requirement ID; first defined in #{seen_ids.fetch(id)}", context)
      end

      validate_requirement_translations!(id, file, context)
      seen_ids[id] = file.basename.to_s
    end

    def validate_effective_compositions!
      base_ids = @requirements_by_sector.fetch(BASE_SECTOR, EMPTY_REQUIREMENTS).map(&:id)

      @requirements_by_sector.except(BASE_SECTOR).each do |sector, requirements|
        duplicate_id = (base_ids & requirements.map(&:id)).first
        next unless duplicate_id

        invalid!(
          @files_by_sector.fetch(sector),
          "duplicate requirement ID; first defined in #{@files_by_sector.fetch(BASE_SECTOR).basename}",
          duplicate_id
        )
      end
    end

    def validate_non_empty_strings!(attributes, file, context)
      (REQUIREMENT_KEYS - [ "parameters" ]).each do |key|
        next if attributes[key].is_a?(String) && attributes[key].present?

        invalid!(file, "#{key} must be a non-empty string", context)
      end
    end

    def validate_requirement_translations!(id, file, context)
      I18n.available_locales.each do |locale|
        %i[title guidance].each do |attribute|
          key = Kyc::PolicyRequirement.translation_key(id, attribute)
          next if I18n.exists?(key, locale, fallback: false)

          invalid!(file, "missing translation for locale #{locale.inspect}: #{key}", context)
        end
      end
    end

    def validate_parameters!(rule, parameters, file, context)
      validate_keys!(
        parameters,
        required: REQUIRED_RULE_PARAMETERS.fetch(rule),
        allowed: RULE_PARAMETERS.fetch(rule),
        file: file,
        context: context
      )

      document_type = parameters["document_type"]
      unless KycDocument.document_types.key?(document_type)
        invalid!(file, "unknown document_type #{document_type.inspect}", context)
      end

      case rule
      when "required_document"
        invalid!(file, "unsupported subject #{parameters['subject'].inspect}", context) unless SUBJECTS.include?(parameters["subject"])
      when "document_validity"
        validate_validity_parameters!(parameters, file, context)
      end
    end

    def validate_validity_parameters!(parameters, file, context)
      invalid!(file, "version must be a positive integer", context) unless parameters["version"].is_a?(Integer) && parameters["version"].positive?
      invalid!(file, "unsupported mode #{parameters['mode'].inspect}", context) unless VALIDITY_MODES.include?(parameters["mode"])
      validate_string_array!(parameters["required_dates"], "required_dates", file, context, allow_empty: false)
      validate_integer_array!(parameters["warning_thresholds"], "warning_thresholds", file, context)
      invalid!(file, "document_validity blocking must be true", context) unless parameters["blocking"] == true

      if parameters["mode"] == "freshness"
        unless parameters["required_dates"].include?("issued")
          invalid!(file, "freshness mode requires an issued date", context)
        end
        max_age = parameters["max_age_months"]
        invalid!(file, "max_age_months must be a positive integer for freshness mode", context) unless max_age.is_a?(Integer) && max_age.positive?
      else
        unless parameters["required_dates"].include?("expiry")
          invalid!(file, "expires mode requires an expiry date", context)
        end
        if parameters.key?("max_age_months") && !parameters["max_age_months"].nil?
          invalid!(file, "max_age_months is only supported for freshness mode", context)
        end
      end

      parse_effective_date!(parameters, file, context)
    end

    def validate_string_array!(value, key, file, context, allow_empty:)
      valid = value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) && entry.present? }
      valid &&= value.any? unless allow_empty
      invalid!(file, "#{key} must be an array of non-empty strings", context) unless valid
    end

    def validate_integer_array!(value, key, file, context)
      valid = value.is_a?(Array) && value.all? { |entry| entry.is_a?(Integer) && entry.positive? }
      invalid!(file, "#{key} must be an array of positive integers", context) unless valid
    end

    def parse_effective_date!(parameters, file, context)
      value = parameters["effective_from"]
      unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        invalid!(file, "effective_from must be a quoted ISO date", context)
      end

      parameters["effective_from"] = Date.iso8601(value)
    rescue Date::Error
      invalid!(file, "effective_from must be a valid ISO date", context)
    end

    def validate_keys!(mapping, required:, allowed:, file:, context: nil)
      unknown = mapping.keys - allowed
      invalid!(file, "unknown key(s): #{unknown.join(', ')}", context) if unknown.any?

      missing = required - mapping.keys
      invalid!(file, "missing key(s): #{missing.join(', ')}", context) if missing.any?
    end

    def build_requirement(attributes)
      parameters = deep_freeze(attributes.fetch("parameters"))
      Kyc::PolicyRequirement.new(
        id: attributes.fetch("id").freeze,
        rule: attributes.fetch("rule").freeze,
        outcome: attributes.fetch("outcome").freeze,
        source: attributes.fetch("source").freeze,
        parameters: parameters
      )
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each { |key, entry| deep_freeze(key); deep_freeze(entry) }
      when Array
        value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end

    def validate_requested_sector!(sector)
      return if Applicant.sectors.key?(sector)

      raise ArgumentError, "unsupported Applicant sector #{sector.inspect}"
    end

    def invalid!(file, message, context = nil)
      location = file.basename.to_s
      location = "#{location} requirement #{context.inspect}" if context
      raise InvalidPolicy, "#{location}: #{message}"
    end
  end
end
