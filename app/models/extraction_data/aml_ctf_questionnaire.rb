# frozen_string_literal: true

module ExtractionData
  class AmlCtfQuestionnaire < Base
    register_as :aml_ctf_questionnaire

    attribute :respondent_name, :string
    attribute :entity_name, :string
    attribute :date_completed, :date
    attribute :version, :string

    validates :respondent_name, presence: true
  end
end
