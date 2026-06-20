# frozen_string_literal: true

module ExtractionData
  class FundsFlowDiagram < Base
    register_as :funds_flow_diagram

    attribute :entities, :string
    attribute :flow_description, :string
  end
end
