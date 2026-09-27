# frozen_string_literal: true

class OnboardingApplication < ApplicationRecord
  STEPS = %w[company fulfilment currencies processing pricing volumes countries principals review].freeze

  belongs_to :applicant

  enum :status, { draft: 0, submitted: 1 }, default: :draft

  validates :applicant_id, uniqueness: true
  validates :current_step, inclusion: { in: STEPS }
  validate :completed_steps_are_known

  private

  def completed_steps_are_known
    return if completed_steps.all? { |step| STEPS.include?(step) }

    errors.add(:completed_steps, :invalid)
  end
end
