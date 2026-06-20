# frozen_string_literal: true

module ExtractionData
  class SourceOfWealthQuestionnaire < Base
    register_as :source_of_wealth_questionnaire

    attribute :respondent_name, :string
    attribute :date_completed, :date
    attribute :wealth_sources, :string
    attribute :signed, :boolean

    validates :respondent_name, presence: true
  end
end
