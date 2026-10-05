# frozen_string_literal: true

class OnboardingCountry < ApplicationRecord
  # Sample list until the full ISO 3166-1 list is wired in; display names live under `countries.names`.
  SAMPLE_CODES = %w[GB IE US DE FR ES NL AU CA SG].freeze

  belongs_to :onboarding_application, inverse_of: :onboarding_countries

  before_validation :normalize_code

  validates :code,
            inclusion: { in: SAMPLE_CODES },
            uniqueness: { scope: :onboarding_application_id, case_sensitive: false }

  def name
    I18n.t("countries.names.#{code}", default: code)
  end

  private

  def normalize_code
    self.code = code.to_s.strip.upcase
  end
end
