# frozen_string_literal: true

module OnboardingApplications
  # MH-388: one read model answering "what do we know about this application,
  # what is missing and what should happen next", across the form (database)
  # and the onboarding chat (OnboardingSession#stage_data). Read-only.
  #
  # Origins are coarse and derived from where a value was read:
  #   :applicant  held on the application records (entered via the form or chat)
  #   :chat       only present in the chat's session data
  #   :registry   fetched from a company registry
  #   :document   extracted from an uploaded document
  #   :staff      verified by staff
  # Origins for the company fields come from persisted provenance (MH-389).
  class Snapshot
    Fact = Data.define(:key, :label, :value, :origin)
    Principal = Data.define(:name, :role, :origin, :missing)
    NextAction = Data.define(:step, :message)
    Conflict = Data.define(:field, :held_value, :held_source, :proposed_value, :proposed_source)

    # The only facts that may be sent to an LLM. Widen deliberately, here, if
    # that ever becomes appropriate (e.g. private inference). Addresses and
    # anything personal stay out.
    LLM_FACT_KEYS = %i[
      company_name company_number company_type country_of_incorporation sector business_description
      operating_licence domains target_countries processing_currencies settlement_currencies
    ].freeze

    CHAT_STEP = "chat"
    DOCUMENTS_STEP = "documents"
    # Steps with no validation context of their own.
    UNVALIDATED_STEPS = %w[volumes review].freeze
    SOURCE_ORIGINS = { applicant_declared: :applicant, registry: :registry, document_extracted: :document,
                       staff_verified: :staff }.freeze
    PRINCIPAL_ORIGINS = { "registry_fetched" => :registry, "document_extracted" => :document,
                          "applicant_declared" => :applicant }.freeze

    # key, label, how to read it from the database, how to read it from the
    # chat's stage data, and which chat fields it answers.
    FACT_DEFINITIONS = [
      { key: :company_name, label: "Company name", answers: [ %w[company_info company_name] ],
        db: ->(application) { application.applicant.company_name },
        chat: ->(data) { data.dig("company_info", "company_name") } },
      { key: :company_number, label: "Company number", answers: [ %w[company_info registration_number] ],
        db: ->(application) { application.applicant.company_number },
        chat: ->(data) { data.dig("company_info", "registration_number") } },
      { key: :company_type, label: "Company type", answers: [ %w[company_info company_type] ],
        chat: ->(data) { data.dig("company_info", "company_type") } },
      { key: :country_of_incorporation, label: "Country of incorporation",
        answers: [ %w[company_info country_of_incorporation] ],
        chat: ->(data) { data.dig("company_info", "country_of_incorporation") } },
      { key: :registered_address, label: "Registered address", answers: [ %w[company_info registered_address] ],
        db: ->(application) { Snapshot.format_address(application.applicant.primary_business_address) },
        chat: ->(data) { data.dig("company_info", "registered_address") } },
      { key: :trading_address, label: "Trading address",
        db: ->(application) { Snapshot.format_address(application.applicant.trading_address) } },
      { key: :sector, label: "Sector", answers: [ %w[business_activity industry] ],
        db: ->(application) { application.applicant.sector&.to_s&.humanize },
        chat: ->(data) { data.dig("business_activity", "industry") } },
      { key: :business_description, label: "Business description",
        answers: [ %w[business_activity business_description] ],
        db: ->(application) { application.business_model_description },
        chat: ->(data) { data.dig("business_activity", "business_description") } },
      { key: :operating_licence, label: "Operating licence",
        db: ->(application) { application.operating_licence } },
      { key: :domains, label: "Website domains", answers: [ %w[business_activity website] ],
        db: ->(application) { application.applicant.applicant_domains.map(&:name).join(", ") },
        chat: ->(data) { data.dig("business_activity", "website") } },
      { key: :target_countries, label: "Target countries",
        db: ->(application) { application.target_country_names.join(", ") } },
      { key: :processing_currencies, label: "Processing currencies",
        db: ->(application) { application.processing_currencies.map(&:code).sort.join(", ") } },
      { key: :settlement_currencies, label: "Settlement currencies",
        db: ->(application) { application.settlement_currencies.map(&:code).sort.join(", ") } },
      { key: :descriptor, label: "Statement descriptor", db: ->(application) { application.descriptor } },
      { key: :jurisdictions, label: "Jurisdictions of operation",
        chat: lambda { |data|
          Array(data.dig("jurisdictions", "items")).filter_map { |item| item["country"] }.join(", ")
        } }
    ].freeze

    def self.for(application) = new(application)

    def self.format_address(address)
      return if address.nil?

      [ address.line1, address.line2, address.city, address.postcode, address.country ].compact_blank.join(", ")
    end

    def initialize(application)
      # A fresh copy: gathering gaps runs validations, which can adjust attributes in memory.
      @application = OnboardingApplication.find(application.id)
      @applicant = @application.applicant
    end

    def current_step = application.current_step

    def facts
      @facts ||= FACT_DEFINITIONS.filter_map { |definition| build_fact(definition) }
    end

    # Gaps by step, in form order; chat-only questions sit under "chat".
    def missing
      @missing ||= form_gaps.merge(chat_gaps).compact_blank.freeze
    end

    def principals
      @principals ||= applicant.kyc_principals.active.order(:created_at).map do |principal|
        Principal.new(
          name: principal.name,
          role: principal.role,
          origin: PRINCIPAL_ORIGINS.fetch(principal.source, :applicant),
          missing: principal_gaps(principal)
        )
      end
    end

    def required_documents = document_requirements.required

    def missing_documents = document_requirements.missing

    def next_action
      step = form_step_with_gap
      return NextAction.new(step: step, message: missing[step].first) if step
      return NextAction.new(step: CHAT_STEP, message: missing[CHAT_STEP].first) if missing[CHAT_STEP].present?
      return if missing_documents.empty?

      NextAction.new(step: DOCUMENTS_STEP, message: "Upload #{missing_documents.first.humanize.downcase}")
    end

    # Registry-checkable company fields that still only rest on the applicant's word.
    def unverified
      return [] unless registry_could_verify?

      facts.select { |fact| Provenance::CompanyFields::FIELDS.include?(fact.key.to_s) && fact.origin == :applicant }
           .map(&:key)
    end

    def conflicts
      @conflicts ||= applicant.data_conflicts.status_open.order(:detected_at).map do |conflict|
        Conflict.new(field: conflict.field, held_value: conflict.held_value, held_source: conflict.held_source,
                     proposed_value: conflict.proposed_value, proposed_source: conflict.proposed_source)
      end
    end

    def for_llm
      {
        current_step: current_step,
        facts: facts.select { |fact| LLM_FACT_KEYS.include?(fact.key) }.to_h { |fact| [ fact.key, fact.value ] },
        missing: missing,
        missing_documents: missing_documents,
        principals: principals.map { |principal| principal.to_h.slice(:name, :role, :missing) },
        next_action: next_action&.to_h
      }
    end

    private

    attr_reader :application, :applicant

    def chat_data
      @chat_data ||= applicant.onboarding_session&.stage_data || {}
    end

    def build_fact(definition)
      database_value = definition[:db]&.call(application).presence
      return Fact.new(key: definition[:key], label: definition[:label], value: database_value, origin: database_origin(definition[:key])) if database_value

      chat_value = definition[:chat]&.call(chat_data).presence
      Fact.new(key: definition[:key], label: definition[:label], value: chat_value, origin: :chat) if chat_value
    end

    def database_origin(key)
      return :applicant unless Provenance::CompanyFields::FIELDS.include?(key.to_s)

      SOURCE_ORIGINS.fetch(Provenance::CompanyFields.source_for(applicant, key.to_s), :applicant)
    end

    def registry_could_verify?
      applicant.company_number.present? && Registry::Lookup.client_class_for(applicant.registry_jurisdiction).present?
    end

    def form_gaps
      steps = OnboardingApplication::STEPS - UNVALIDATED_STEPS
      steps.index_with do |step|
        application.valid?(step.to_sym)
        ErrorMessages.for(application)
      end
    end

    def form_step_with_gap
      return current_step if missing[current_step].present?

      OnboardingApplication::STEPS.find { |step| missing[step].present? }
    end

    # Required chat questions that neither the chat nor the application has answered.
    def chat_gaps
      return {} unless applicant.onboarding_session

      gaps = Onboarding::StateMachine::STAGES.reject(&:looping).flat_map do |stage|
        stage.fields.select(&:required).filter_map do |field|
          field.name.to_s.humanize unless chat_field_answered?(stage.name.to_s, field.name.to_s)
        end
      end
      { CHAT_STEP => gaps }
    end

    def chat_field_answered?(stage, field)
      return true if chat_data.dig(stage, field).present?

      facts.any? { |fact| answered_by?(fact, stage, field) }
    end

    def answered_by?(fact, stage, field)
      definition = FACT_DEFINITIONS.find { |candidate| candidate[:key] == fact.key }
      Array(definition[:answers]).include?([ stage, field ])
    end

    def principal_gaps(principal)
      principal.valid?(:self_service)
      details = principal.errors.attribute_names.map { |attribute| attribute.to_s.humanize }
      details + missing_principal_documents(principal)
    end

    def missing_principal_documents(principal)
      held = applicant.kyc_documents.not_superseded.where(kyc_principal_id: principal.id).pluck(:document_type)
      {
        "Proof of identity" => Kyc::DocumentCategory.types_for(:identity),
        "Proof of address" => Kyc::DocumentCategory.types_for(:proof_of_address)
      }.filter_map { |label, types| label if (held & types.map(&:to_s)).empty? }
    end

    def document_requirements
      @document_requirements ||= RequirementsAssessment.document_requirements(applicant)
    end
  end
end
