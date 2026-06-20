# frozen_string_literal: true

module DocumentClassifiers
  class DeclarationOfTrust < Base
    register handler: :declaration_of_trust

    def self.pattern
      /declaration\s*(of\s*)?trust/i
    end
  end
end
