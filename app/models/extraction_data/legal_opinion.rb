# frozen_string_literal: true

module ExtractionData
  class LegalOpinion < Base
    register_as :legal_opinion

    attribute :subject_entity, :string
    attribute :issuing_firm, :string
    attribute :issue_date, :date
    attribute :jurisdiction, :string
    attribute :opinion_summary, :string

    validates :subject_entity, presence: true
  end
end
