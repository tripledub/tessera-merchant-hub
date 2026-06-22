# frozen_string_literal: true

module ExtractionData
  class GroupStructureChart < Base
    register_as :group_structure_chart

    attribute :entities, :string
    attribute :edges, :string
  end
end
