# frozen_string_literal: true

module Provenance
  # MH-389: the trust-order rules for the company fields a registry can supply
  # (name and number). Every write goes through here so the source of a value is
  # recorded and a lower-ranked source never replaces a higher-ranked one
  # silently: the applicant's value is still kept (they are the arbiter), but the
  # previous value is retained and a conflict is recorded for staff.
  module CompanyFields
    FIELDS = %w[company_name company_number].freeze
    RECORD_TYPE = "Applicant"

    module_function

    def source_for(applicant, field)
      provenance_for(applicant, field)&.source&.to_sym || :applicant_declared
    end

    # Writes `value` to the applicant and reconciles provenance and conflicts.
    def apply!(applicant:, field:, value:, source:, provider: nil, retrieved_at: nil)
      field = field.to_s
      value = value.to_s.strip.presence
      return if value.nil?

      previous = applicant.public_send(field)
      applicant.update!(field => value) unless previous == value
      reconcile!(applicant: applicant, field: field, previous: previous, value: value,
                 source: source.to_sym, provider: provider, retrieved_at: retrieved_at)
    end

    # For paths that have already saved the applicant's value (the application form).
    def record_applicant_edit!(applicant:, field:, previous_value:)
      field = field.to_s
      value = applicant.public_send(field).to_s.strip.presence
      return if value.nil?

      reconcile!(applicant: applicant, field: field, previous: previous_value, value: value, source: :applicant_declared)
    end

    # A later registry check disagrees with what we hold: record it, change nothing.
    def flag_difference!(applicant:, field:, registry_value:, provider:)
      field = field.to_s
      held = applicant.public_send(field).presence
      return if registry_value.blank? || held.nil? || held == registry_value

      record_conflict!(applicant, field,
                       held_value: held, held_source: source_for(applicant, field),
                       held_provider: provenance_for(applicant, field)&.provider,
                       proposed_value: registry_value, proposed_source: :registry, proposed_provider: provider)
    end

    def reconcile!(applicant:, field:, previous:, value:, source:, provider: nil, retrieved_at: nil)
      held_source = source_for(applicant, field)
      held_provider = provenance_for(applicant, field)&.provider
      changed = previous.present? && previous != value
      outranked = DataProvenance.rank(source) < DataProvenance.rank(held_source)

      if changed
        store_provenance!(applicant, field, source: source, provider: provider, retrieved_at: retrieved_at,
                                            previous_value: previous)
        if outranked
          record_conflict!(applicant, field, held_value: previous, held_source: held_source, held_provider: held_provider,
                                             proposed_value: value, proposed_source: source, proposed_provider: provider)
        else
          refresh_open_proposal!(applicant, field, value, source)
        end
      elsif provenance_for(applicant, field).nil? || !outranked
        store_provenance!(applicant, field, source: source, provider: provider, retrieved_at: retrieved_at)
      end

      resolve_converged_conflict!(applicant, field, value)
    end
    private_class_method :reconcile!

    def store_provenance!(applicant, field, source:, provider:, retrieved_at:, previous_value: nil)
      provenance = provenance_for(applicant, field) || DataProvenance.new(
        applicant: applicant, record_type: RECORD_TYPE, record_id: applicant.id, field: field
      )
      provenance.assign_attributes(source: source, provider: provider, retrieved_at: retrieved_at)
      provenance.previous_value = previous_value if previous_value
      provenance.save!
    end
    private_class_method :store_provenance!

    def record_conflict!(applicant, field, held_value:, held_source:, held_provider:, proposed_value:, proposed_source:,
                         proposed_provider:)
      conflict = applicant.data_conflicts.status_open.find_or_initialize_by(
        record_type: RECORD_TYPE, record_id: applicant.id, field: field
      )
      conflict.update!(held_value: held_value, held_source: held_source, held_provider: held_provider,
                       proposed_value: proposed_value, proposed_source: proposed_source,
                       proposed_provider: proposed_provider, detected_at: Time.current)
    end
    private_class_method :record_conflict!

    # The same source changing its mind again: the conflict keeps what was held
    # originally and follows the latest proposal.
    def refresh_open_proposal!(applicant, field, value, source)
      applicant.data_conflicts.status_open.where(field: field, proposed_source: source).find_each do |conflict|
        conflict.update!(proposed_value: value, detected_at: Time.current)
      end
    end
    private_class_method :refresh_open_proposal!

    # Once the stored value matches what the conflict said was held, nothing disagrees any more.
    def resolve_converged_conflict!(applicant, field, value)
      applicant.data_conflicts.status_open.where(field: field, held_value: value).find_each do |conflict|
        conflict.update!(status: :resolved)
      end
    end
    private_class_method :resolve_converged_conflict!

    def provenance_for(applicant, field)
      DataProvenance.find_by(record_type: RECORD_TYPE, record_id: applicant.id, field: field)
    end
  end
end
