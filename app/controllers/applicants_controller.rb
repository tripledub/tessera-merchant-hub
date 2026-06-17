# frozen_string_literal: true

class ApplicantsController < ApplicationController
  expose(:applicants) {
    scope = policy_scope(Applicant)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.where("name ILIKE :q OR company_name ILIKE :q", q: q)
    end
    scope.order(:name)
  }

  expose(:applicant) { Applicant.find(params[:id]) }

  def index
    authorize Applicant, :index?
    @pagy, @applicants = pagy(:offset, applicants)
  end

  def show
    authorize applicant
    @kyc_principals = applicant.kyc_principals.order(:name)
    @kyc_documents  = applicant.kyc_documents.includes(:kyc_principal).order(:created_at)
  end

  def new
    authorize Applicant, :new?
    @applicant = Applicant.new
  end

  def create
    authorize Applicant, :create?
    @applicant = Applicant.new(applicant_params)
    if @applicant.save
      redirect_to applicant_path(@applicant), notice: t("flash.applicants.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize applicant
  end

  def update
    authorize applicant
    if applicant.update(applicant_params)
      redirect_to applicant_path(applicant), notice: t("flash.applicants.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def applicant_params
    params.require(:applicant).permit(:name, :company_name, :contact_email, :country, :country_code, :address_line1, :city, :support_url)
  end
end
