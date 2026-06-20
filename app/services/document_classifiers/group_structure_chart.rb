# frozen_string_literal: true

module DocumentClassifiers
  class GroupStructureChart < Base
    register handler: :group_structure_chart

    def self.pattern
      /group\s*structure/i
    end
  end
end
