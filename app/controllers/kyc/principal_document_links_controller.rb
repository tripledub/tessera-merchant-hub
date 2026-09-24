# frozen_string_literal: true

class Kyc::PrincipalDocumentLinksController < ApplicationController
  expose(:kyc_principal) { KycPrincipal.find(params[:principal_id]) }

  def new
    authorize kyc_principal, :show?
    @unlinked_documents = kyc_principal.applicant.kyc_documents.where(kyc_principal_id: nil).order(created_at: :desc)
  end

  def create
    authorize kyc_principal, :update?
    @document = kyc_principal.applicant.kyc_documents.find(params[:document_id])
    # MH-333: "override_linked", not "exact" — this is a reviewer's manual
    # pick, not an algorithmic name/DOB match, and the two need to read
    # differently. Matches Kyc::PrincipalMatchOverrideService's own use of
    # override_linked for its manual-link path.
    @document.update!(kyc_principal: kyc_principal, match_method: "override_linked", match_confidence: 1.0)
    Kyc::AddressPopulationService.call(@document)
    Kyc::BusinessAddressPopulationService.call(@document)
    respond_to do |format|
      format.turbo_stream
    end
  end
end
