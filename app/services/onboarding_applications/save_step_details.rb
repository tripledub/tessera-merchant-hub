# frozen_string_literal: true

module OnboardingApplications
  class SaveStepDetails
    def self.call(application:, step:, attributes:)
      saved = application.transaction do
        application.lock!
        raise Advance::StepConflict unless application.current_step == step || application.completed_steps.include?(step)

        application.assign_attributes(attributes)
        application.save(context: step.to_sym)
      end

      return false unless saved

      Advance.call(application: application, step: step) if application.current_step == step
      true
    rescue Advance::StepConflict
      application.reload
      raise unless application.completed_steps.include?(step)

      true
    end
  end
end
