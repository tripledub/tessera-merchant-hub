# frozen_string_literal: true

module DocumentClassifiers
  class SourceOfWealthQuestionnaire < Base
    register handler: :source_of_wealth_questionnaire

    def self.pattern
      /source\s*(of\s*)?wealth/i
    end
  end
end
