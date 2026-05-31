# frozen_string_literal: true

module Tessera
  class Payment < ReadOnlyRecord
    self.table_name = "payments"

    has_many :audit_events,
      class_name: "Tessera::AuditEvent",
      foreign_key: :payment_id,
      inverse_of: :payment

    has_many :webhook_deliveries,
      class_name: "Tessera::WebhookDelivery",
      foreign_key: :payment_id,
      inverse_of: :payment

    scope :for_shop, ->(shop_id) { where(shop_id: shop_id) }
  end
end
