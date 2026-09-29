# frozen_string_literal: true

class Portal::ApplicationsController < Portal::BaseController
  def show
    created = current_applicant.onboarding_application.nil?
    @application = OnboardingApplications::FindOrCreate.call(applicant: current_applicant)
    authorize @application

    return redirect_to portal_application_path(step: @application.current_step) if params[:step].blank? && !created

    @step = params[:step].presence || @application.current_step
    return head :not_found unless OnboardingApplication::STEPS.include?(@step)
    return redirect_to portal_application_path(step: @application.current_step) unless accessible_step?(@step)

    prepare_company_details if @step == "company"
  end

  def update
    @application = OnboardingApplications::FindOrCreate.call(applicant: current_applicant)
    authorize @application
    step = params.require(:step)
    return update_company if step == "company"

    OnboardingApplications::Advance.call(application: @application, step: step)
    redirect_to portal_application_path(step: @application.current_step)
  rescue OnboardingApplications::Advance::StepConflict
    redirect_to portal_application_path(step: @application.current_step), alert: t("portal.applications.progress_conflict")
  end

  private

  def accessible_step?(step)
    step == @application.current_step || @application.completed_steps.include?(step)
  end

  def update_company
    if OnboardingApplications::SaveCompanyDetails.call(application: @application, attributes: company_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "company"
      prepare_company_details
      render :show, status: :unprocessable_content
    end
  end

  def prepare_company_details
    @application.applicant.build_registered_address(primary: true) unless @application.applicant.registered_address
    @application.applicant.build_trading_address(primary: true) unless @application.applicant.trading_address
    @application.applicant.applicant_domains.build if @application.applicant.applicant_domains.empty?
  end

  def company_params
    params.require(:onboarding_application).permit(
      :eu_entity_details,
      :referrer,
      :business_model_description,
      :test_login_details,
      :operating_licence,
      applicant_attributes: [
        :id,
        :company_name,
        :company_number,
        :sector,
        { registered_address_attributes: %i[id line1 line2 city postcode country],
          trading_address_attributes: %i[id line1 line2 city postcode country],
          applicant_domains_attributes: %i[id name _destroy] }
      ]
    )
  end
end
