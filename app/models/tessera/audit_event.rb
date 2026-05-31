# frozen_string_literal: true

module Tessera
  class AuditEvent < ReadOnlyRecord
    self.table_name = "audit_events"

    belongs_to :payment,
      class_name: "Tessera::Payment",
      foreign_key: :payment_id,
      inverse_of: :audit_events

    scope :chronological, -> { order(occurred_at: :asc) }
  end
end
