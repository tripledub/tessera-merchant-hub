# frozen_string_literal: true

module Synthetic
  # MH-311: loads and validates every scenario under config/synthetic/scenarios/.
  # A scenario is the single source of truth tying together a fake registry
  # company (MH-310), the Synthetic::Persona records playing its officers
  # (MH-309, referenced by slug — never duplicated inline), and the
  # documents to generate for them, so a tester never has to keep three
  # separate data sources in sync by hand.
  class ScenarioCatalogue
    DIR = Rails.root.join("config/synthetic/scenarios")
    REQUIRED_KEYS = %w[id title company_number people ground_truth qase_cases].freeze
    REQUIRED_PERSON_KEYS = %w[persona role].freeze
    REQUIRED_DOCUMENT_KEYS = %w[type options].freeze

    class InvalidScenario < StandardError; end

    Document = Data.define(:type, :options)
    Person = Data.define(:persona_slug, :role, :documents) do
      def persona
        Synthetic::Persona.find_by!(slug: persona_slug)
      end
    end
    Scenario = Data.define(:id, :title, :company_number, :people, :ground_truth, :qase_cases) do
      def self.policy_class
        Synthetic::ScenarioPolicy
      end
    end

    def self.all
      @all ||= files.map { |file| load_and_validate(file) }
    end

    def self.find(id)
      all.find { |scenario| scenario.id == id.to_s } ||
        raise(ActiveRecord::RecordNotFound, "no synthetic scenario '#{id}'")
    end

    def self.reset!
      @all = nil
    end

    def self.files
      Dir.glob(DIR.join("*.yml")).sort
    end
    private_class_method :files

    def self.load_and_validate(file)
      data = YAML.safe_load_file(file)
      errors = validate(data, file)
      raise InvalidScenario, errors.join("; ") if errors.any?

      build(data)
    end
    private_class_method :load_and_validate

    def self.validate(data, file)
      errors = []
      missing = REQUIRED_KEYS - data.keys
      return [ "#{file}: missing #{missing.join(', ')}" ] if missing.any?

      unless data["people"].is_a?(Array) && data["people"].any?
        errors << "#{file}: people must be a non-empty array"
        return errors
      end
      data["people"].each_with_index { |person, i| errors.concat(validate_person(person, file, i)) }

      unless data["qase_cases"].is_a?(Array) && data["qase_cases"].any?
        errors << "#{file}: qase_cases must be a non-empty array"
      end

      errors
    end
    private_class_method :validate

    def self.validate_person(person, file, index)
      errors = []
      missing = REQUIRED_PERSON_KEYS - person.keys
      errors << "#{file}: person #{index} missing #{missing.join(', ')}" if missing.any?

      Array(person["documents"]).each_with_index do |document, doc_index|
        missing_doc = REQUIRED_DOCUMENT_KEYS - document.keys
        if missing_doc.any?
          errors << "#{file}: person #{index} document #{doc_index} missing #{missing_doc.join(', ')}"
        end
      end
      errors
    end
    private_class_method :validate_person

    def self.build(data)
      people = data["people"].map do |person|
        documents = Array(person["documents"]).map do |doc|
          Document.new(type: doc["type"], options: (doc["options"] || {}).symbolize_keys)
        end
        Person.new(persona_slug: person["persona"], role: person["role"], documents: documents)
      end

      Scenario.new(
        id: data["id"], title: data["title"], company_number: data["company_number"],
        people: people, ground_truth: data["ground_truth"], qase_cases: data["qase_cases"]
      )
    end
    private_class_method :build
  end
end
