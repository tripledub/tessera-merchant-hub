# frozen_string_literal: true

class OnboardingApplication < ApplicationRecord
  STEPS = %w[company fulfilment currencies processing pricing volumes countries principals review].freeze

  belongs_to :applicant

  accepts_nested_attributes_for :applicant, update_only: true

  enum :status, { draft: 0, submitted: 1 }, default: :draft

  validates :applicant_id, uniqueness: true
  validates :current_step, inclusion: { in: STEPS }
  validate :completed_steps_are_known
  validates :business_model_description, :operating_licence, presence: true, on: :company
  validate :company_identity_is_complete, on: :company
  validate :company_addresses_are_complete, on: :company
  validate :company_has_a_domain, on: :company
  validates :delivery_over_seven_days, :full_payment_before_delivery, :takes_deposits,
            inclusion: { in: [ true, false ] }, on: :fulfilment
  validates :service_requirements, :integration_type, presence: true, on: :fulfilment
  validates :deposit_percentage,
            presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 },
            if: :takes_deposits?,
            on: :fulfilment
  validates :remaining_balance_due, presence: true, if: :takes_deposits?, on: :fulfilment

  before_validation :clear_deposit_details, if: -> { takes_deposits == false }

  private

  def completed_steps_are_known
    return if completed_steps.all? { |step| STEPS.include?(step) }

    errors.add(:completed_steps, :invalid)
  end

  def company_identity_is_complete
    errors.add(:company_name, :blank) if applicant.company_name.blank?
    errors.add(:company_number, :blank) if applicant.company_number.blank?
  end

  def company_addresses_are_complete
    validate_company_address(:registered_address)
    validate_company_address(:trading_address)
  end

  def company_has_a_domain
    return if applicant.applicant_domains.reject(&:marked_for_destruction?).any?

    errors.add(:domains, :blank)
  end

  def validate_company_address(name)
    address = applicant.public_send(name)
    errors.add(name, address ? :invalid : :blank) unless address&.valid?
  end

  def clear_deposit_details
    self.deposit_percentage = nil
    self.remaining_balance_due = nil
  end
end
