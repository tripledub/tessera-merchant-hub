# frozen_string_literal: true

module Kyc
  # Records the domains a proof-of-domain document evidences (MH-295, MH-299).
  # A name the applicant doesn't have becomes a pending, extracted candidate for
  # a psp_admin to accept or reject. A name they already have, in any case and
  # any review status, keeps its status (so a rejected domain is never
  # resurrected) and simply gains this document as further evidence.
  #
  # Links are created by id rather than by assigning records: a candidate that
  # fails validation would otherwise stay on the document's association via
  # inverse_of and break the document's own save (found in MH-295).
  class DomainEvidenceRecorder
    def self.call(document:, names:)
      new(document, names).call
    end

    def initialize(document, names)
      @document = document
      @names = names
    end

    # Returns the domains newly visible to the applicant as a result of this
    # call (MH-328) — so a caller in a layer allowed to touch presentation
    # (e.g. ExtractKycDocumentJob, via ApplicantDomainBroadcaster) can
    # broadcast them. Excludes a name that already had a domain row before
    # this call: nothing changed for the Domains tab to show.
    def call
      @names.filter_map { |name| record(name) }
    end

    private

    def record(name)
      existing = find_domain(name)
      domain = existing || create_candidate(name) || find_domain(name)
      return unless domain

      ApplicantDomainDocument.find_or_create_by!(applicant_domain_id: domain.id, kyc_document_id: @document.id)
      domain unless existing
    rescue ActiveRecord::RecordNotUnique
      nil # lost a race to a concurrent insert of the same domain or link
    end

    def find_domain(name)
      applicant.applicant_domains.find_by("lower(name) = ?", name.downcase)
    end

    # A name on the blocklist is created already rejected (and says so), so it
    # stays visible and auditable but nobody has to reject it by hand.
    def create_candidate(name)
      status = if DomainBlocklistEntry.blocks?(name)
        { review_status: :rejected, rejection_reason: :blocklisted }
      else
        { review_status: :pending }
      end

      domain = applicant.applicant_domains.create(name: name, source: :extracted, **status)
      domain if domain.persisted?
    end

    def applicant
      @document.applicant
    end
  end
end
