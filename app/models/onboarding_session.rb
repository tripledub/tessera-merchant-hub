# frozen_string_literal: true

class OnboardingSession < ApplicationRecord
  belongs_to :applicant
  has_many :onboarding_messages, dependent: :destroy, inverse_of: :onboarding_session

  enum :current_stage, {
    company_info: 0,
    directors_ubos: 1,
    ownership: 2,
    business_activity: 3,
    jurisdictions: 4,
    document_collection: 5
  }, default: :company_info

  enum :status, { in_progress: 0, completed: 1, abandoned: 2 }, default: :in_progress

  validates :applicant_id, uniqueness: true
end
