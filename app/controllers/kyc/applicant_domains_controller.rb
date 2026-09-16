# frozen_string_literal: true

class Kyc::ApplicantDomainsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) if params[:applicant_id] }
  expose(:applicant_domain) { params[:id] ? ApplicantDomain.find(params[:id]) : ApplicantDomain.new(applicant: applicant) }

  def new
    authorize applicant_domain
  end

  def create
    authorize applicant_domain
    if applicant_domain.update(applicant_domain_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to applicant_path(applicant_domain.applicant), notice: t("flash.applicant_domains.create_success") }
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    authorize applicant_domain
    applicant = applicant_domain.applicant
    applicant_domain.destroy!
    redirect_to applicant_path(applicant), notice: t("flash.applicant_domains.destroy_success")
  end

  private

  def applicant_domain_params
    params.require(:applicant_domain).permit(:name)
  end
end
