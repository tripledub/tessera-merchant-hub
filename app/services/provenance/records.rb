# frozen_string_literal: true

module Provenance
  # MH-389: provenance for a whole record (a principal, an entity), as opposed to
  # one field of it. Records that carry their own legacy `source` enum are read
  # into the same vocabulary when no provenance row exists.
  module Records
    LEGACY_SOURCES = {
      "registry_fetched" => :registry,
      "document_extracted" => :document_extracted,
      "applicant_declared" => :applicant_declared
    }.freeze

    module_function

    def source_for(record)
      provenance_for(record)&.source&.to_sym || legacy_source(record) || :applicant_declared
    end

    # Never lowers a record's provenance: a lower-ranked source leaves the row alone.
    def record!(applicant:, record:, source:, provider: nil, retrieved_at: nil)
      source = source.to_sym
      provenance = provenance_for(record) || DataProvenance.new(
        applicant: applicant, record_type: record.class.name, record_id: record.id, field: ""
      )
      return provenance if provenance.persisted? && DataProvenance.rank(source) < DataProvenance.rank(provenance.source)

      provenance.update!(source: source, provider: provider, retrieved_at: retrieved_at)
      provenance
    end

    def provenance_for(record)
      DataProvenance.find_by(record_type: record.class.name, record_id: record.id, field: "")
    end
    private_class_method :provenance_for

    def legacy_source(record)
      return unless record.respond_to?(:source)

      LEGACY_SOURCES[record.source.to_s]
    end
    private_class_method :legacy_source
  end
end
