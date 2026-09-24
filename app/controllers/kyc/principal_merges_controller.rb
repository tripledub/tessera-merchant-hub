# frozen_string_literal: true

# MH-331: merges a duplicate KycPrincipal row into the one a reviewer opened
# (kyc_principal survives; the picked candidate is soft-deleted onto it).
class Kyc::PrincipalMergesController < ApplicationController
  expose(:kyc_principal) { KycPrincipal.find(params[:principal_id]) }

  def new
    authorize kyc_principal, :merge?
    @candidates = candidate_principals
  end

  def create
    authorize kyc_principal, :merge?
    loser = candidate_principals.find(params[:loser_id])
    result = Kyc::PrincipalMergeService.call(survivor: kyc_principal, loser: loser)

    if result.success?
      redirect_to kyc_principal_path(kyc_principal), notice: t("flash.kyc_principals.merge_success")
    else
      @candidates = candidate_principals
      @error = result.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  private

  def candidate_principals
    kyc_principal.applicant.kyc_principals.active.where.not(id: kyc_principal.id).order(:name)
  end
end
