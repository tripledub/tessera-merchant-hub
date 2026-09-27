# frozen_string_literal: true

class OnboardingApplicationPresenter < BasePresenter
  presents :onboarding_application

  def steps
    OnboardingApplication::STEPS.map do |step|
      {
        key: step,
        label: t("portal.applications.steps.#{step}"),
        completed: onboarding_application.completed_steps.include?(step),
        current: onboarding_application.current_step == step
      }
    end
  end

  def progress_percentage
    (onboarding_application.completed_steps.size.fdiv(OnboardingApplication::STEPS.size) * 100).round
  end
end
