# frozen_string_literal: true

# A one-time code emailed to an applicant's address (MH-404). Only a keyed digest
# of the code is stored: an HMAC with a secret derived from the app secret,
# salted with the record's id, so a leaked database alone cannot be brute-forced
# (there are only a million six-digit codes).
class ApplicantSignInCode < ApplicationRecord
  CODE_LENGTH = 6
  LIFETIME = 10.minutes
  MAX_ATTEMPTS = 5
  # The code travels to the email job encrypted for this long and for this purpose.
  MAIL_PURPOSE = :applicant_sign_in_code
  MAIL_TOKEN_LIFETIME = 15.minutes

  belongs_to :applicant
  belongs_to :applicant_invitation, optional: true
  belongs_to :applicant_user, optional: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, :code_digest, :expires_at, presence: true

  before_validation :assign_id, on: :create

  def self.generate_code
    format("%0#{CODE_LENGTH}d", SecureRandom.random_number(10**CODE_LENGTH))
  end

  def self.digest_for(id:, code:)
    key = Rails.application.key_generator.generate_key("applicant-sign-in-code", 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, "#{id}:#{code}")
  end

  def matches?(code)
    ActiveSupport::SecurityUtils.secure_compare(self.class.digest_for(id: id, code: code.to_s), code_digest)
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def locked?
    invalidated_at.present? || attempts >= MAX_ATTEMPTS
  end

  private

  # The id is the salt, so it has to exist before the digest is made.
  def assign_id
    self.id ||= SecureRandom.uuid
  end
end
