# frozen_string_literal: true

class Portal::ApplicationsController < Portal::BaseController
  def show
    created = current_applicant.onboarding_application.nil?
    @application = OnboardingApplications::FindOrCreate.call(applicant: current_applicant)
    authorize @application

    return redirect_to portal_application_path(step: @application.current_step) if params[:step].blank? && !created

    @step = params[:step].presence || @application.current_step
    return head :not_found unless OnboardingApplication::STEPS.include?(@step)
    redirect_to portal_application_path(step: @application.current_step) unless accessible_step?(@step)
  end

  def update
    @application = OnboardingApplications::FindOrCreate.call(applicant: current_applicant)
    authorize @application
    OnboardingApplications::Advance.call(application: @application, step: params.require(:step))
    redirect_to portal_application_path(step: @application.current_step)
  rescue OnboardingApplications::Advance::StepConflict
    redirect_to portal_application_path(step: @application.current_step), alert: t("portal.applications.progress_conflict")
  end

  private

  def accessible_step?(step)
    step == @application.current_step || @application.completed_steps.include?(step)
  end
end
