# frozen_string_literal: true

module Tessera
  class WebhookDelivery < ReadOnlyRecord
    self.table_name = "webhook_deliveries"

    belongs_to :payment,
      class_name: "Tessera::Payment",
      foreign_key: :payment_id,
      inverse_of: :webhook_deliveries
  end
end
