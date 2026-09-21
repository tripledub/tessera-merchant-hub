# frozen_string_literal: true

# MH-251: staff attesting "this applicant has no corporate owners" is what lets
# an empty ownership graph count as compliant.
class Kyc::OwnershipAttestationsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }

  def create
    authorize applicant, :attest_no_corporate_owners?

    if applicant.can_attest_no_corporate_owners?
      applicant.attest_no_corporate_owners!(by: current_user)
      redirect_to applicant_path(applicant), notice: t("flash.kyc_ownership_attestations.attested")
    else
      redirect_to applicant_path(applicant), alert: t("flash.kyc_ownership_attestations.entities_exist")
    end
  end

  def destroy
    authorize applicant, :attest_no_corporate_owners?

    applicant.revoke_no_corporate_owners_attestation!
    redirect_to applicant_path(applicant), notice: t("flash.kyc_ownership_attestations.removed")
  end
end
