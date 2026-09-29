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
    validate_company_address(:primary_business_address, error_attribute: :registered_address)
    validate_company_address(:trading_address)
  end

  def company_has_a_domain
    return if applicant.applicant_domains.reject(&:marked_for_destruction?).any?

    errors.add(:domains, :blank)
  end

  def validate_company_address(name, error_attribute: name)
    address = applicant.public_send(name)
    errors.add(error_attribute, address ? :invalid : :blank) unless address&.valid?
  end
end
