# frozen_string_literal: true

class ApplicantDomain < ApplicationRecord
  DOMAIN_FORMAT = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/i

  include Commentable

  # The reason a hand-added domain is trusted, entered on the Add domain form.
  # Not persisted on the domain: Kyc::AddDomainByHand stores it as a Comment.
  attr_accessor :justification

  belongs_to :applicant, foreign_key: :applicant_id, inverse_of: :applicant_domains
  has_many :evidence_links, class_name: "ApplicantDomainDocument", dependent: :delete_all, inverse_of: :applicant_domain
  has_many :evidence_documents, through: :evidence_links, source: :kyc_document

  enum :verification_status, { unverified: 0, verified: 1 }, default: :unverified

  # Extracted domains start `pending` and need a psp_admin's accept/reject;
  # hand-added ones are accepted on creation (the column default). Rejected
  # rows are kept so re-extraction never resurrects them.
  enum :review_status, { pending: 0, accepted: 1, rejected: 2 }, default: :accepted
  enum :source, { manual: 0, extracted: 1 }, default: :manual, prefix: :source

  # Why a rejected domain was rejected: by a person, or by the blocklist (MH-298).
  # Only meaningful while rejected, so it is defaulted and cleared to match.
  enum :rejection_reason, { manual: 0, blocklisted: 1 }, prefix: :rejected_as

  before_validation :normalize_rejection_reason

  validates :name, presence: true, format: { with: DOMAIN_FORMAT }, uniqueness: { scope: :applicant_id, case_sensitive: false }

  private

  def normalize_rejection_reason
    self.rejection_reason = rejected? ? (rejection_reason || :manual) : nil
  end
end
