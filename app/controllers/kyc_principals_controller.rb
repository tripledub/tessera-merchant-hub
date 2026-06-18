# frozen_string_literal: true

class KycPrincipalsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) if params[:applicant_id] }
  expose(:kyc_principal) { params[:id] ? KycPrincipal.find(params[:id]) : KycPrincipal.new(applicant: applicant) }

  def new
    authorize kyc_principal
  end

  def create
    authorize kyc_principal
    if kyc_principal.update(kyc_principal_params)
      redirect_to applicant_path(kyc_principal.applicant), notice: t("flash.kyc_principals.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize kyc_principal
  end

  def update
    authorize kyc_principal
    if kyc_principal.update(kyc_principal_params)
      redirect_to applicant_path(kyc_principal.applicant), notice: t("flash.kyc_principals.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize kyc_principal
    applicant = kyc_principal.applicant
    kyc_principal.destroy!
    redirect_to applicant_path(applicant), notice: t("flash.kyc_principals.destroy_success")
  end

  private

  def kyc_principal_params
    params.require(:kyc_principal).permit(:name, :role)
  end
end
