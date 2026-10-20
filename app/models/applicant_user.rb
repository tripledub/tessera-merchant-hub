# frozen_string_literal: true

class ApplicantUser < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable

  belongs_to :applicant

  # Passwords are optional (MH-408). When one is set, applicants need a longer
  # minimum than the admin users (Devise's default of 6 is kept for them), and
  # are told by email whenever it is set or changed.
  self.password_length = 8..128
  self.send_password_change_notification = true

  # An applicant can exist with only an email (MH-413): one-time-code sign-in
  # creates the user from a verified address, with no name and no password. The
  # old password registration form (retired in MH-409) still requires all three,
  # by saving with this context.
  validates :first_name, :last_name, presence: true, on: :password_registration

  # The name is optional and only used to greet the applicant (MH-407): tidy it,
  # store a blank one as nil, and keep it a sensible length.
  NAME_MAX_LENGTH = 100
  normalizes :first_name, :last_name, with: ->(name) { name.strip.presence }
  validates :first_name, :last_name, length: { maximum: NAME_MAX_LENGTH }
  validates :password, presence: true, on: :password_registration, if: -> { password.nil? }

  def password_set?
    encrypted_password.present?
  end

  # The calm "set a password" banner: only for someone with no password who has
  # not dismissed it and has started (completed at least one form step).
  def password_prompt_due?
    !password_set? && password_prompt_dismissed_at.nil? && applicant&.onboarding_application&.completed_steps.present?
  end

  protected

  # Devise's :validatable asks for a password on every new record. Here it is
  # only checked when one is actually being set, and then it follows the usual
  # rules (length, confirmation). A user with no password cannot sign in with
  # one: Devise rejects any attempt against an empty stored password.
  def password_required?
    !password.nil? || !password_confirmation.nil?
  end
end
