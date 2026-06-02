# frozen_string_literal: true

module Tessera
  # Read-only view of tessera-core's merchants (control-plane entity).
  # Owned by tessera-core (ADR-007); MerchantHub never writes to it.
  class Merchant < ReadOnlyRecord
    self.table_name = "merchants"

    has_many :shops,
      class_name: "Tessera::Shop",
      foreign_key: :merchant_id,
      primary_key: :merchant_id,
      inverse_of: :merchant
  end
end
