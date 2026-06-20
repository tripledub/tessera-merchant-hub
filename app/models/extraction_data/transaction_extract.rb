# frozen_string_literal: true

module ExtractionData
  class TransactionExtract < Base
    register_as :transaction_extract

    attribute :entity_name, :string
    attribute :period_start, :date
    attribute :period_end, :date
    attribute :currency, :string
    attribute :total_volume, :string
    attribute :transaction_count, :string
  end
end
