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

    def call
      @names.each { |name| record(name) }
    end

    private

    def record(name)
      domain = find_domain(name) || create_candidate(name) || find_domain(name)
      return unless domain

      ApplicantDomainDocument.find_or_create_by!(applicant_domain_id: domain.id, kyc_document_id: @document.id)
    rescue ActiveRecord::RecordNotUnique
      nil # lost a race to a concurrent insert of the same domain or link
    end

    def find_domain(name)
      applicant.applicant_domains.find_by("lower(name) = ?", name.downcase)
    end

    def create_candidate(name)
      domain = applicant.applicant_domains.create(name: name, source: :extracted, review_status: :pending)
      domain if domain.persisted?
    end

    def applicant
      @document.applicant
    end
  end
end
