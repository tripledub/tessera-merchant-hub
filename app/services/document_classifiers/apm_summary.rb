# frozen_string_literal: true

module DocumentClassifiers
  class ApmSummary < Base
    register handler: :apm_summary

    def self.pattern
      /apm\s*summary/i
    end
  end
end
