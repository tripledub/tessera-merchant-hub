# frozen_string_literal: true

module ExtractionData
  class GroupStructureChart < Base
    register_as :group_structure_chart

    attribute :parent_company, :string
    attribute :entities, :string
  end
end
