# frozen_string_literal: true

module Onboarding
  module StateMachine
    class IncompleteStageError < StandardError; end
    class InvalidTransitionError < StandardError; end

    Field = Data.define(:name, :type, :required, :options, :required_when)
    Stage = Data.define(:name, :fields, :looping)

    STAGES = [
      Stage.new(
        name: :company_info,
        looping: false,
        fields: [
          Field.new(name: :company_name, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :registration_number, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :company_type, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :registered_address, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :country_of_incorporation, type: :string, required: true, options: nil, required_when: nil)
        ]
      ),
      Stage.new(
        name: :directors_ubos,
        looping: true,
        fields: [
          Field.new(name: :full_name, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :date_of_birth, type: :date, required: true, options: nil, required_when: nil),
          Field.new(name: :nationality, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :role, type: :option, required: true, options: %w[director shareholder both],
            required_when: nil),
          Field.new(name: :residential_address, type: :string, required: false, options: nil, required_when: nil)
        ]
      ),
      Stage.new(
        name: :ownership,
        looping: true,
        fields: [
          Field.new(name: :owner, type: :reference, required: true, options: nil, required_when: nil),
          Field.new(name: :owned_entity, type: :reference, required: true, options: nil, required_when: nil),
          Field.new(name: :percentage, type: :decimal, required: false, options: nil,
            required_when: ->(data) { data["relationship_type"] == "equity" }),
          Field.new(name: :relationship_type, type: :option, required: true, options: %w[equity nominee contractual],
            required_when: nil)
        ]
      ),
      Stage.new(
        name: :business_activity,
        looping: false,
        fields: [
          Field.new(name: :industry, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :business_description, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :website, type: :string, required: false, options: nil, required_when: nil),
          Field.new(name: :expected_monthly_volume, type: :string, required: false, options: nil, required_when: nil),
          Field.new(name: :expected_transaction_count, type: :string, required: false, options: nil,
            required_when: nil)
        ]
      ),
      Stage.new(
        name: :jurisdictions,
        looping: true,
        fields: [
          Field.new(name: :country, type: :string, required: true, options: nil, required_when: nil),
          Field.new(name: :licence_type, type: :string, required: false, options: nil, required_when: nil),
          Field.new(name: :licence_number, type: :string, required: false, options: nil, required_when: nil)
        ]
      ),
      Stage.new(
        name: :document_collection,
        looping: false,
        # Completion for this stage is determined by document upload logic, not field collection.
        fields: []
      )
    ].freeze

    STAGE_NAMES = STAGES.map(&:name).freeze
    STAGES_BY_NAME = STAGES.index_by(&:name).freeze
    FIELDS_BY_NAME = STAGES.flat_map(&:fields).index_by(&:name).freeze
    FIELD_NAMES = STAGES.flat_map(&:fields).map(&:name).freeze
    raise "duplicate field name" if FIELD_NAMES.size != FIELDS_BY_NAME.size

    module_function

    def current_stage(session)
      session.current_stage.to_sym
    end

    def missing_fields(session)
      stage = stage_definition(current_stage(session))
      data = data_for_missing_fields(session, stage)

      required_fields_for(stage, data).filter_map do |field|
        field.name unless field_valid?(field, data[field.name.to_s])
      end
    end

    def validate_field(field, value)
      definition = FIELDS_BY_NAME[field.to_sym]
      return { valid: false, error: "unknown field" } unless definition

      field_valid?(definition, value) ? { valid: true } : { valid: false, error: "#{field} is invalid" }
    end

    def stage_complete?(session)
      stage = stage_definition(current_stage(session))
      return non_looping_stage_complete?(session, stage) unless stage.looping

      looping_stage_complete?(session, stage)
    end

    def advance!(session)
      raise IncompleteStageError, "#{current_stage(session)} is incomplete" unless stage_complete?(session)

      stage = current_stage(session)
      next_stage = stage_after(stage)
      completed_stages = (session.completed_stages + [ stage.to_s ]).uniq

      if next_stage
        session.update!(current_stage: next_stage, completed_stages: completed_stages)
        next_stage
      else
        session.update!(completed_stages: completed_stages, status: :completed)
        :completed
      end
    end

    def can_go_back?(session)
      stage_index(current_stage(session)).positive?
    end

    def go_back!(session, stage)
      target_stage = stage.to_sym
      current_index = stage_index(current_stage(session))
      target_index = stage_index(target_stage)

      if target_index >= current_index
        raise InvalidTransitionError, "cannot go back from #{current_stage(session)} to #{target_stage}"
      end

      # Keep stage_data intact so applicants can revise prior answers without losing work.
      session.update!(
        current_stage: target_stage,
        completed_stages: session.completed_stages.first(target_index)
      )
      target_stage
    end

    def stage_definition(stage)
      STAGES_BY_NAME.fetch(stage.to_sym)
    end
    private_class_method :stage_definition

    def data_for_missing_fields(session, stage)
      return stage_data(session, stage) unless stage.looping

      payload = stage_data(session, stage)
      current_item = payload["current_item"]
      return current_item if current_item.present?
      return {} if complete_loop_items(payload["items"], stage).empty?

      {}
    end
    private_class_method :data_for_missing_fields

    def non_looping_stage_complete?(session, stage)
      required_fields_for(stage, stage_data(session, stage)).all? do |field|
        field_valid?(field, stage_data(session, stage)[field.name.to_s])
      end
    end
    private_class_method :non_looping_stage_complete?

    def looping_stage_complete?(session, stage)
      payload = stage_data(session, stage)
      items = Array(payload["items"])
      current_item = payload["current_item"]

      return false if current_item.present? && missing_fields_for(stage, current_item).any?

      complete_loop_items(items, stage).any?
    end
    private_class_method :looping_stage_complete?

    def complete_loop_items(items, stage)
      items.select { |item| missing_fields_for(stage, item).empty? }
    end
    private_class_method :complete_loop_items

    def missing_fields_for(stage, data)
      required_fields_for(stage, data).filter_map do |field|
        field.name unless field_valid?(field, data[field.name.to_s])
      end
    end
    private_class_method :missing_fields_for

    def required_fields_for(stage, data)
      stage.fields.select { |field| field.required || field.required_when&.call(data) }
    end
    private_class_method :required_fields_for

    def field_valid?(field, value)
      return false if value.blank?

      case field.type
      when :string, :reference
        value.to_s.strip.present?
      when :date
        Date.iso8601(value.to_s)
        true
      when :decimal
        BigDecimal(value.to_s)
        true
      when :option
        field.options.include?(value.to_s)
      else
        false
      end
    rescue ArgumentError
      false
    end
    private_class_method :field_valid?

    def stage_data(session, stage)
      session.stage_data.fetch(stage.name.to_s, {})
    end
    private_class_method :stage_data

    def stage_after(stage)
      STAGE_NAMES[stage_index(stage) + 1]
    end
    private_class_method :stage_after

    def stage_index(stage)
      STAGE_NAMES.index(stage.to_sym) || raise(InvalidTransitionError, "unknown stage #{stage}")
    end
    private_class_method :stage_index
  end
end
