# frozen_string_literal: true

class OnboardingApplication < ApplicationRecord
  STEPS = %w[company fulfilment currencies processing payments descriptor volumes countries principals review].freeze

  belongs_to :applicant

  has_many :onboarding_currencies, dependent: :destroy, inverse_of: :onboarding_application
  has_many :onboarding_countries, dependent: :destroy, autosave: true, inverse_of: :onboarding_application
  has_many :processing_currencies, -> { where(kind: :processing) },
           class_name: "OnboardingCurrency", inverse_of: :onboarding_application
  has_many :settlement_currencies, -> { where(kind: :settlement) },
           class_name: "OnboardingCurrency", inverse_of: :onboarding_application

  accepts_nested_attributes_for :applicant, update_only: true
  accepts_nested_attributes_for :processing_currencies, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :settlement_currencies, allow_destroy: true, reject_if: :all_blank

  enum :status, { draft: 0, submitted: 1 }, default: :draft

  validates :applicant_id, uniqueness: true
  validates :current_step, inclusion: { in: STEPS }
  validate :completed_steps_are_known
  validates :business_model_description, :operating_licence, presence: true, on: %i[company submission]
  validate :company_identity_is_complete, on: %i[company submission]
  validate :company_addresses_are_complete, on: %i[company submission]
  validates :delivery_over_seven_days, :full_payment_before_delivery, :takes_deposits,
            inclusion: { in: [ true, false ] }, on: %i[fulfilment submission]
  validates :service_requirements, :integration_type, presence: true, on: %i[fulfilment submission]
  validates :deposit_percentage,
            presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 },
            if: :takes_deposits?,
            on: %i[fulfilment submission]
  validates :remaining_balance_due, presence: true, if: :takes_deposits?, on: %i[fulfilment submission]
  validate :currency_collections_are_present, on: %i[currencies submission]
  validate :target_countries_are_present, on: %i[countries submission]
  validates :currently_accepts_card_payments, inclusion: { in: [ true, false ] }, on: %i[processing submission]
  validates :current_acquirer, presence: true, if: :currently_accepts_card_payments?, on: %i[processing submission]
  validates :uses_shopping_cart, :takes_recurring_payments,
            inclusion: { in: [ true, false ] }, on: %i[payments submission]
  validates :shopping_cart_provider, presence: true, if: :uses_shopping_cart?, on: %i[payments submission]
  validates :sends_recurring_payment_receipts, :sends_recurring_payment_advance_notifications,
            inclusion: { in: [ true, false ] }, if: :takes_recurring_payments?, on: %i[payments submission]
  validates :descriptor, :descriptor_company_number, :descriptor_company_city,
            presence: true, on: %i[descriptor submission]
  validate :applicant_has_principals, on: %i[principals submission]
  validate :applicant_principals_are_complete, on: %i[principals submission]

  before_validation :clear_deposit_details, if: -> { takes_deposits == false }
  before_validation :clear_current_acquirer, if: -> { currently_accepts_card_payments == false }
  before_validation :clear_shopping_cart_provider, if: -> { uses_shopping_cart == false }
  before_validation :clear_recurring_payment_details, if: -> { takes_recurring_payments == false }

  def target_country_codes
    active_target_countries.map(&:code)
  end

  def target_country_codes=(codes)
    wanted = Array(codes).compact_blank.map { |code| code.to_s.strip.upcase }.uniq
    onboarding_countries.each { |country| country.mark_for_destruction unless wanted.include?(country.code) }
    (wanted - onboarding_countries.map(&:code)).each { |code| onboarding_countries.build(code: code) }
  end

  def target_country_names
    active_target_countries.map(&:name).sort
  end

  private

  def completed_steps_are_known
    return if completed_steps.all? { |step| STEPS.include?(step) }

    errors.add(:completed_steps, :invalid)
  end

  def company_identity_is_complete
    errors.add(:company_name, :blank) if applicant.company_name.blank?
  end

  def company_addresses_are_complete
    validate_company_address(:primary_business_address, error_attribute: :registered_address)
    validate_company_address(:trading_address)
  end

  def validate_company_address(name, error_attribute: name)
    address = applicant.public_send(name)
    errors.add(error_attribute, address ? :invalid : :blank) unless address&.valid?
  end

  def clear_deposit_details
    self.deposit_percentage = nil
    self.remaining_balance_due = nil
  end

  def currency_collections_are_present
    errors.add(:processing_currencies, :blank) unless active_currencies(processing_currencies).any?
    errors.add(:settlement_currencies, :blank) unless active_currencies(settlement_currencies).any?
  end

  def target_countries_are_present
    errors.add(:onboarding_countries, :blank) if active_target_countries.empty?
  end

  def active_target_countries
    onboarding_countries.reject(&:marked_for_destruction?)
  end

  def active_currencies(collection)
    collection.reject(&:marked_for_destruction?)
  end

  def clear_current_acquirer
    self.current_acquirer = nil
  end

  def clear_shopping_cart_provider
    self.shopping_cart_provider = nil
  end

  def clear_recurring_payment_details
    self.sends_recurring_payment_receipts = nil
    self.sends_recurring_payment_advance_notifications = nil
  end

  def applicant_has_principals
    principals = applicant.kyc_principals.to_a.reject(&:merged?).reject(&:marked_for_destruction?)
    return if principals.any?

    # i18n-tasks-use t("activerecord.errors.models.onboarding_application.attributes.applicant.principals_blank")
    errors.add(:applicant, :principals_blank)
  end

  def applicant_principals_are_complete
    principals = applicant.kyc_principals.to_a.reject(&:merged?).reject(&:marked_for_destruction?)
    errors.add(:applicant, :invalid) unless principals.all? { |principal| principal.valid?(:self_service) }
  end
end
