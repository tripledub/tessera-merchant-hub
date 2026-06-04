# frozen_string_literal: true

module Tessera
  # Read-only view of tessera-core's shops (control-plane entity).
  # Owned by tessera-core (ADR-007); MerchantHub never writes to it.
  class Shop < ReadOnlyRecord
    self.table_name = "shops"

    belongs_to :merchant,
      class_name: "Tessera::Merchant",
      foreign_key: :merchant_id,
      primary_key: :merchant_id,
      inverse_of: :shops,
      optional: true

    scope :for_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }

    # Use the business key in URLs rather than the internal uuid.
    def to_param
      shop_id
    end

    # Core gateway account id (GW-52). Falls back to shop_id for legacy rows.
    def integration_account_id
      self[:integration_account_id].presence || shop_id
    end
  end
end
