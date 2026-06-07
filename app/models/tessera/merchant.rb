# frozen_string_literal: true

module Tessera
  # ADR-007: merchants are now owned by MerchantHub.
  # This alias keeps existing controller/policy references working without changes.
  Merchant = ::Merchant
end
