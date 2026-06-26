# frozen_string_literal: true

module Onboarding
  module DataCaptureService
    ROLE_MAP = {
      "director" => "director",
      "shareholder" => "shareholder",
      "both" => "director_and_psc"
    }.freeze

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
        validation = Onboarding::StateMachine.validate_field(field, value)
        result[field.to_s] = value if validation[:valid]
      end
    end
    private_class_method :valid_extracted_data

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
      current_item = stage_payload.fetch("current_item", {}).merge(valid_data)

      stage_payload["current_item"] = current_item
      stage_data[stage] = stage_payload
      session.update!(stage_data: stage_data)

      commit_current_item!(session) if Onboarding::StateMachine.missing_fields(session).empty?
    end
    private_class_method :capture_looping_stage

    def commit_current_item!(session)
      stage = Onboarding::StateMachine.current_stage(session).to_s
      stage_data = session.stage_data.deep_dup
      stage_payload = stage_data.fetch(stage)
      current_item = stage_payload.fetch("current_item")
      stage_payload["items"] = Array(stage_payload["items"]) + [ current_item ]
      stage_payload.delete("current_item")
      stage_data[stage] = stage_payload

      session.update!(stage_data: stage_data)
      persist_stage_record(session, stage, current_item)
    end
    private_class_method :commit_current_item!

    def persist_stage_record(session, stage, data)
      case stage
      when "directors_ubos"
        create_principal!(session, data)
      when "ownership"
        create_ownership_edge!(session, data)
      end
    end
    private_class_method :persist_stage_record

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
