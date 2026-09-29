# frozen_string_literal: true

class ApplicantInvitation < ApplicationRecord
  TOKEN_BYTES = 32
  class NotClaimable < StandardError; end

  belongs_to :applicant
  belongs_to :invited_by, class_name: "User"
  belongs_to :claimed_by, class_name: "ApplicantUser", optional: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, presence: true, uniqueness: true

  scope :usable, -> { where(claimed_at: nil, revoked_at: nil) }

  def self.issue!(applicant:, email:, invited_by:)
    token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    invitation = create!(
      applicant: applicant,
      email: email,
      invited_by: invited_by,
      token_digest: digest(token)
    )

    [ invitation, token ]
  end

  def self.find_usable_by_token(token)
    return if token.blank?

    usable.find_by(token_digest: digest(token))
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end
  private_class_method :digest

  def claim!(applicant_user)
    with_lock do
      unless claimed_at.nil? && revoked_at.nil? && applicant_user.applicant_id == applicant_id &&
          applicant_user.email.casecmp?(email)
        raise NotClaimable
      end

      update!(claimed_by: applicant_user, claimed_at: Time.current)
    end
  end
end
