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

  before_action :ensure_applicant_delete_enabled!, only: :destroy

  def index
    authorize Applicant, :index?
    @pagy, @applicants = pagy(:offset, applicants)
  end

  def show
    authorize applicant
    @kyc_principals = applicant.kyc_principals.order(:name)
    @kyc_documents  = applicant.kyc_documents.includes(:kyc_principal)
                        .order(Arel.sql("CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 WHEN 3 THEN 2 WHEN 2 THEN 3 END"), :created_at)
  end

  def tab
    authorize applicant, :show?
    tab_name = params[:tab]
    allowed = %w[overview principals documents ownership compliance summary]
    head(:not_found) and return unless allowed.include?(tab_name)

    @kyc_principals = applicant.kyc_principals.order(:name) if tab_name == "principals"
    @kyc_documents = applicant.kyc_documents.includes(:kyc_principal)
                       .order(Arel.sql("CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 WHEN 3 THEN 2 WHEN 2 THEN 3 END"), :created_at) if tab_name == "documents"

    locals = { applicant: applicant }
    locals[:calculator] = Kyc::CompletenessCalculator.for(applicant) if tab_name == "overview"

    render partial: "applicants/tabs/#{tab_name}", locals: locals, layout: false
  end

  def new
    authorize Applicant, :new?
    @applicant = Applicant.new
  end

  def registry_preview
    authorize Applicant, :new?
    @company_number = params.dig(:applicant, :company_number).to_s.strip
    @preview_result = Registry::CompaniesHouseUkClient.new.fetch(company_number: @company_number) if @company_number.present?
  end

  def create
    authorize Applicant, :create?
    @applicant = Applicant.new(new_applicant_params)
    if @applicant.save
      run_registry_lookup(@applicant)
    else
      render :new, status: :unprocessable_content
    end
  end

  def registry_lookup
    authorize applicant, :update?
    run_registry_lookup(applicant)
  end

  def edit
    authorize applicant
  end

  def update
    authorize applicant
    if applicant.update(applicant_params)
      redirect_to applicant_path(applicant), notice: t("flash.applicants.update_success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize applicant
    result = Applicants::Deletion.call(applicant)
    if result.errors.none?
      redirect_to applicants_path, notice: t("flash.applicants.destroy_success")
    else
      redirect_to applicant_path(applicant), alert: result.errors.full_messages.to_sentence
    end
  end

  private

  def run_registry_lookup(target_applicant)
    result = Registry::Lookup.call(applicant: target_applicant)
    if result.success
      target_applicant.update(company_name: result.registry_profile.company_name)
      Kyc::PrincipalsFromRegistry.call(result.registry_profile)
      Kyc::OwnershipFromRegistry.call(result.registry_profile)
      redirect_to applicant_path(target_applicant), notice: t("flash.applicants.registry_lookup_success")
    else
      redirect_to applicant_path(target_applicant), alert: t("flash.applicants.registry_lookup_failed")
    end
  end

  def new_applicant_params
    params.require(:applicant).permit(:name, :company_number).merge(registry_jurisdiction: "gb")
  end

  def applicant_params
    params.require(:applicant).permit(:name, :company_name, :contact_email, :country, :country_code, :address_line1, :city, :support_url)
  end

  def ensure_applicant_delete_enabled!
    raise ActiveRecord::RecordNotFound unless Rails.application.config.x.applicant_delete_enabled
  end
end
