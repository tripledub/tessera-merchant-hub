# frozen_string_literal: true

class OnboardingCurrency < ApplicationRecord
  belongs_to :onboarding_application, inverse_of: :onboarding_currencies

  enum :kind, { processing: 0, settlement: 1 }, validate: true

  before_validation :normalize_code

  validates :code,
            presence: true,
            format: { with: /\A[A-Z]{3}\z/ },
            uniqueness: { scope: %i[onboarding_application_id kind], case_sensitive: false }

  private

  def normalize_code
    self.code = code.to_s.strip.upcase
  end
end
