# frozen_string_literal: true

module DocumentClassifiers
  class LegalOpinion < Base
    register handler: :legal_opinion

    def self.pattern
      /legal\s*opinion/i
    end
  end
end
