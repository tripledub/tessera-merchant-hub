# frozen_string_literal: true

# A registrar or similar domain that is never the applicant's own (GoDaddy etc.).
# A candidate extracted from a proof-of-domain document that matches an entry is
# created already rejected, so nobody has to reject it by hand (MH-298). Names are
# registrable domains, stored lowercase; Kyc::AddBlocklistEntry normalises input.
class DomainBlocklistEntry < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_name

  validates :name, presence: true, format: { with: ApplicantDomain::DOMAIN_FORMAT },
                   uniqueness: { case_sensitive: false }

  # Exact match only: "shop.godaddy.com" or "notgodaddy.com" are not blocked by
  # "godaddy.com". Extraction reduces every candidate to its registrable domain.
  def self.blocks?(name)
    return false if name.blank?

    where("lower(name) = ?", name.to_s.strip.downcase).exists?
  end

  private

  def normalize_name
    self.name = name.strip.downcase if name
  end
end
