# frozen_string_literal: true

module ApplicantDomainBroadcaster
  extend ActiveSupport::Concern

  private

  # MH-328: a domain discovered by Kyc::DomainEvidenceRecorder is created from
  # inside ExtractKycDocumentJob, well after the Documents/Domains tab was
  # rendered — without this, the new row only appears on a full page reload.
  # Appends the row and clears the tbody's empty-state placeholder, same
  # table _domains.html.erb renders into on first load.
  def broadcast_new_applicant_domain(domain)
    Turbo::StreamsChannel.broadcast_remove_to(
      "applicant_#{domain.applicant_id}_domains",
      target: "applicant-domains-empty"
    )
    Turbo::StreamsChannel.broadcast_append_to(
      "applicant_#{domain.applicant_id}_domains",
      target: "applicant-domains-list",
      partial: "kyc/applicant_domains/domain_row",
      locals: { applicant_domain: domain }
    )
  end
end
