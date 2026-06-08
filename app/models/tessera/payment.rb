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

    scope :with_statuses, ->(statuses) {
      values = Array(statuses).reject(&:blank?)
      values.any? ? where(status: values) : none
    }

    scope :from_date, ->(d) {
      where("inserted_at >= ?", Date.parse(d).beginning_of_day)
    }

    scope :to_date, ->(d) {
      where("inserted_at <= ?", Date.parse(d).end_of_day)
    }

    scope :with_reference, ->(ref) {
      where("merchant_reference ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(ref)}%")
    }

    scope :amount_at_least, ->(n) { where("amount >= ?", n.to_i) }
    scope :amount_at_most,  ->(n) { where("amount <= ?", n.to_i) }
  end
end
