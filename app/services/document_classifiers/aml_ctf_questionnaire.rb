# frozen_string_literal: true

module DocumentClassifiers
  class AmlCtfQuestionnaire < Base
    register handler: :aml_ctf_questionnaire

    def self.pattern
      /aml\s*ctf\s*questionnaire/i
    end
  end
end
