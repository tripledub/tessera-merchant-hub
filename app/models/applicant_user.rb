# frozen_string_literal: true

class ApplicantUser < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable

  belongs_to :applicant

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

  protected

  # Devise's :validatable asks for a password on every new record. Here it is
  # only checked when one is actually being set, and then it follows the usual
  # rules (length, confirmation). A user with no password cannot sign in with
  # one: Devise rejects any attempt against an empty stored password.
  def password_required?
    !password.nil? || !password_confirmation.nil?
  end
end
