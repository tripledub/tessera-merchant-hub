# frozen_string_literal: true

# Attach or detach a proof-of-domain document as evidence for a domain, by hand
# from the Domains tab (MH-299). Extraction also creates these links, through
# Kyc::DomainEvidenceRecorder. Neither direction changes the domain's review
# status: accepting a domain is never gated on evidence.
class Kyc::EvidenceLinksController < ApplicationController
  expose(:applicant_domain) { ApplicantDomain.find(params[:applicant_domain_id]) }

  def new
    authorize applicant_domain, :attach_evidence?
    @available_documents = available_documents
  end

  def create
    authorize applicant_domain, :attach_evidence?
    # Looked up within the picker's own scope, so another applicant's document,
    # a different document type or an already-linked one is simply not found.
    document = available_documents.find_by(id: params.dig(:evidence_link, :kyc_document_id))
    link = ApplicantDomainDocument.new(applicant_domain_id: applicant_domain.id, kyc_document_id: document&.id)

    if document && link.save
      respond_with_updated_row(t("flash.applicant_domains.evidence_added"), clear_modal: true)
    else
      @available_documents = available_documents
      @error = t("kyc.evidence_links.new.choose_document")
      render :new, formats: :html, status: :unprocessable_content
    end
  end

  def destroy
    link = ApplicantDomainDocument.find(params[:id])
    domain = link.applicant_domain
    authorize domain, :detach_evidence?
    link.destroy!
    respond_with_updated_row(t("flash.applicant_domains.evidence_removed"), domain: domain)
  end

  private

  def available_documents
    applicant_domain.applicant.kyc_documents
                    .proof_of_domain_ownership
                    .where.not(id: applicant_domain.evidence_links.select(:kyc_document_id))
                    .includes(file_attachment: :blob)
                    .order(:created_at)
  end

  def respond_with_updated_row(notice, clear_modal: false, domain: applicant_domain)
    fresh = ApplicantDomain.includes(evidence_links: { kyc_document: { file_attachment: :blob } }).find(domain.id)

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.replace(fresh, partial: "kyc/applicant_domains/domain_row", locals: { applicant_domain: fresh }) ]
        streams << turbo_stream.update("applicant-domain-modal", "") if clear_modal
        render turbo_stream: streams
      end
      format.html { redirect_to applicant_path(fresh.applicant), notice: notice }
    end
  end
end
