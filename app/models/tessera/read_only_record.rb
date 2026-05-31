# frozen_string_literal: true

module Tessera
  # Abstract base class for ActiveRecord models that map to tessera-core tables.
  # These models are strictly read-only: MerchantHub reads from the shared
  # Postgres cluster but never writes to or migrates tessera-core tables.
  class ReadOnlyRecord < ApplicationRecord
    self.abstract_class = true
    self.primary_key = "id"

    def readonly?
      true
    end
  end
end
