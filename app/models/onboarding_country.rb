# frozen_string_literal: true

class OnboardingCountry < ApplicationRecord
  belongs_to :onboarding_application, inverse_of: :onboarding_countries

  before_validation :normalize_code

  validates :code,
            inclusion: { in: ->(_record) { names.keys } },
            uniqueness: { scope: :onboarding_application_id, case_sensitive: false }

  # ISO 3166-1 alpha-2 code => common English name, sorted by name.
  def self.names
    @names ||= ISO3166::Country.translations.sort_by { |_code, name| name }.to_h.freeze
  end

  # [name, code] pairs for building select options.
  def self.options
    names.map { |code, name| [ name, code ] }
  end

  def name
    self.class.names.fetch(code, code)
  end

  private

  def normalize_code
    self.code = code.to_s.strip.upcase
  end
end
