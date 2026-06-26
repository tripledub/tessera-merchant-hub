# frozen_string_literal: true

class OnboardingMessage < ApplicationRecord
  belongs_to :onboarding_session

  enum :role, { bot: 0, applicant: 1 }

  validates :content, presence: true
end
