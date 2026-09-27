# frozen_string_literal: true

class Portal::ApplicationsController < Portal::BaseController
  def show
    created = current_applicant.onboarding_application.nil?
    @application = current_applicant.onboarding_application || current_applicant.create_onboarding_application!
    authorize @application

    return redirect_to portal_application_path(step: @application.current_step) if params[:step].blank? && !created

    @step = params[:step].presence || @application.current_step
    head :not_found unless OnboardingApplication::STEPS.include?(@step)
  end

  def update
    @application = current_applicant.onboarding_application || current_applicant.create_onboarding_application!
    authorize @application
    OnboardingApplications::Advance.call(application: @application, step: params.require(:step))
    redirect_to portal_application_path(step: @application.current_step)
  rescue OnboardingApplications::Advance::StepConflict
    redirect_to portal_application_path(step: @application.current_step), alert: t("portal.applications.progress_conflict")
  end
end
