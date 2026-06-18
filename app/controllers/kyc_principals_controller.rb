# frozen_string_literal: true

class KycPrincipalsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) if params[:applicant_id] }
  expose(:kyc_principal) { params[:id] ? KycPrincipal.find(params[:id]) : KycPrincipal.new(applicant: applicant) }

  def show
    authorize kyc_principal
    @kyc_documents = kyc_principal.kyc_documents.order(created_at: :desc)
    @unlinked_documents = kyc_principal.applicant.kyc_documents.where(kyc_principal_id: nil).order(created_at: :desc)
  end

  def new
    authorize kyc_principal
  end

  def create
    authorize kyc_principal
    if kyc_principal.update(kyc_principal_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to applicant_path(kyc_principal.applicant), notice: t("flash.kyc_principals.create_success") }
      end
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
    params.require(:kyc_principal).permit(:name, :role, :date_of_birth, :email,
                                          :address_line1, :address_line2, :city, :postcode, :country)
  end
end
