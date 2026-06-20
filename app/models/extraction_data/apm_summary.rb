# frozen_string_literal: true

module ExtractionData
  class ApmSummary < Base
    register_as :apm_summary

    attribute :entity_name, :string
    attribute :currency, :string
    attribute :period_end, :date
    attribute :total_volume, :string
  end
end
