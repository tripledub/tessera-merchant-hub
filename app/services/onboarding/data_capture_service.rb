# frozen_string_literal: true

module Onboarding
  module DataCaptureService
    ROLE_MAP = {
      "director" => "director",
      "shareholder" => "shareholder",
      "both" => "director_and_psc"
    }.freeze
    ROLE_SYNONYMS = {
      "director" => "director",
      "company director" => "director",
      "shareholder" => "shareholder",
      "ubo" => "shareholder",
      "ultimate beneficial owner" => "shareholder",
      "psc" => "shareholder",
      "person with significant control" => "shareholder",
      "both" => "both",
      "director and shareholder" => "both",
      "shareholder and director" => "both",
      "director and ubo" => "both",
      "ubo and director" => "both",
      "director and psc" => "both",
      "psc and director" => "both",
      "director_and_psc" => "both"
    }.freeze
    ROLE_OPTIONS = Onboarding::StateMachine::FIELDS_BY_NAME.fetch(:role).options.freeze
    raise "role map does not match onboarding role options" unless ROLE_MAP.keys.sort == ROLE_OPTIONS.sort

    module_function

    def call(session:, extracted_data:)
      valid_data = valid_extracted_data(extracted_data)
      return {} if valid_data.empty?

      case Onboarding::StateMachine.current_stage(session)
      when :directors_ubos, :ownership, :jurisdictions
        capture_looping_stage(session, valid_data)
      else
        capture_non_looping_stage(session, valid_data)
      end

      valid_data
    end

    def valid_extracted_data(extracted_data)
      extracted_data.each_with_object({}) do |(field, value), result|
        normalized_value = normalize_value(field, value)
        validation = Onboarding::StateMachine.validate_field(field, normalized_value)
        result[field.to_s] = normalized_value if validation[:valid]
      end
    end
    private_class_method :valid_extracted_data

    def normalize_value(field, value)
      definition = Onboarding::StateMachine::FIELDS_BY_NAME[field.to_sym]
      return normalize_date(value) if definition&.type == :date
      return normalize_role(value) if field.to_s == "role"

      value
    end
    private_class_method :normalize_value

    def normalize_role(value)
      text = value.to_s.strip.downcase
      ROLE_SYNONYMS.fetch(text, value)
    end
    private_class_method :normalize_role

    def normalize_date(value)
      text = value.to_s.strip
      return text if text.blank?

      parse_date(text).iso8601
    rescue ArgumentError
      value
    end
    private_class_method :normalize_date

    def parse_date(text)
      formats = [
        "%Y-%m-%d",
        "%d/%m/%Y",
        "%d-%m-%Y",
        "%d.%m.%Y",
        "%d %b %Y",
        "%d %B %Y"
      ]
      formats.each do |format|
        return Date.strptime(text, format)
      rescue Date::Error
        next
      end

      raise ArgumentError, "invalid date"
    end
    private_class_method :parse_date

    def capture_non_looping_stage(session, valid_data)
      stage = Onboarding::StateMachine.current_stage(session).to_s
      stage_data = session.stage_data.deep_dup
      stage_data[stage] = stage_data.fetch(stage, {}).merge(valid_data)

      session.update!(stage_data: stage_data)
    end
    private_class_method :capture_non_looping_stage

    def capture_looping_stage(session, valid_data)
      stage = Onboarding::StateMachine.current_stage(session).to_s
      stage_data = session.stage_data.deep_dup
      stage_payload = stage_data.fetch(stage, {})
      return update_latest_looping_item(session, stage, stage_data, stage_payload, valid_data) if latest_item_update?(
        stage,
        stage_payload,
        valid_data
      )

      current_item = stage_payload.fetch("current_item", {}).merge(valid_data)
      stage_payload["current_item"] = current_item
      stage_data[stage] = stage_payload

      session.stage_data = stage_data
      item_complete = Onboarding::StateMachine.missing_fields(session).empty?
      if item_complete
        stage_payload["items"] = Array(stage_payload["items"]) + [ current_item ]
        stage_payload.delete("current_item")
      end

      ActiveRecord::Base.transaction do
        session.update!(stage_data: stage_data)
        persist_stage_record(session, stage, current_item) if item_complete
      end
    end
    private_class_method :capture_looping_stage

    def latest_item_update?(stage, stage_payload, valid_data)
      return false unless stage == "directors_ubos"
      return false if stage_payload["current_item"].present?
      return false if Array(stage_payload["items"]).empty?
      return false if valid_data.key?("full_name")

      valid_data.key?("role")
    end
    private_class_method :latest_item_update?

    def update_latest_looping_item(session, stage, stage_data, stage_payload, valid_data)
      items = Array(stage_payload["items"])
      previous_item = items.last
      updated_item = merge_directors_ubos_item(previous_item, valid_data)
      stage_payload["items"] = items[0...-1] + [ updated_item ]
      stage_data[stage] = stage_payload

      ActiveRecord::Base.transaction do
        session.update!(stage_data: stage_data)
        update_principal!(session, previous_item, updated_item)
      end
    end
    private_class_method :update_latest_looping_item

    def merge_directors_ubos_item(item, valid_data)
      merged_item = item.merge(valid_data)
      return merged_item unless item["role"].present? && valid_data["role"].present?

      merged_item.merge("role" => combined_role(item["role"], valid_data["role"]))
    end
    private_class_method :merge_directors_ubos_item

    def combined_role(existing_role, new_role)
      roles = (role_components(existing_role) + role_components(new_role)).uniq
      return "both" if roles.sort == %w[director shareholder]

      roles.first || new_role
    end
    private_class_method :combined_role

    def role_components(role)
      case role
      when "both"
        %w[director shareholder]
      when "director", "shareholder"
        [ role ]
      else
        []
      end
    end
    private_class_method :role_components

    def persist_stage_record(session, stage, data)
      case stage
      when "directors_ubos"
        create_principal!(session, data)
      when "ownership"
        create_ownership_edge!(session, data)
      when "jurisdictions"
        # Jurisdictions are JSON-only until a dedicated persistence model exists.
        nil
      end
    end
    private_class_method :persist_stage_record

    def update_principal!(session, previous_item, updated_item)
      principal = find_declared_principal(session, previous_item)
      return unless principal

      principal.update!(
        name: updated_item.fetch("full_name"),
        date_of_birth: Date.iso8601(updated_item.fetch("date_of_birth")),
        role: ROLE_MAP.fetch(updated_item.fetch("role")),
        address_line1: updated_item["residential_address"],
        country: updated_item["nationality"]
      )
    end
    private_class_method :update_principal!

    def find_declared_principal(session, item)
      scope = KycPrincipal.where(
        applicant: session.applicant,
        source: :applicant_declared,
        name: item["full_name"]
      )
      date = Date.iso8601(item.fetch("date_of_birth"))
      scope.find_by(date_of_birth: date) || scope.first
    rescue ArgumentError, KeyError
      scope.first
    end
    private_class_method :find_declared_principal

    def create_principal!(session, data)
      KycPrincipal.create!(
        applicant: session.applicant,
        name: data.fetch("full_name"),
        date_of_birth: Date.iso8601(data.fetch("date_of_birth")),
        role: ROLE_MAP.fetch(data.fetch("role")),
        address_line1: data["residential_address"],
        country: data["nationality"],
        source: :applicant_declared
      )
    end
    private_class_method :create_principal!

    def create_ownership_edge!(session, data)
      parent_entity = Kyc::CorporateEntity.find_by!(id: data.fetch("owner"), applicant: session.applicant)
      child_entity = Kyc::CorporateEntity.find_by!(id: data.fetch("owned_entity"), applicant: session.applicant)

      Kyc::OwnershipEdge.create!(
        parent_entity: parent_entity,
        child_entity: child_entity,
        percentage: data["percentage"],
        relationship_type: data.fetch("relationship_type"),
        source: :applicant_declared
      )
    end
    private_class_method :create_ownership_edge!
  end
end
