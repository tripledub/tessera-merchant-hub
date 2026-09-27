# frozen_string_literal: true

module OnboardingApplications
  class Advance
    class StepConflict < StandardError; end

    def self.call(application:, step:)
      application.with_lock do
        raise StepConflict unless application.current_step == step

        completed_steps = (application.completed_steps + [ step ]).uniq
        current_index = OnboardingApplication::STEPS.index(step)
        next_step = OnboardingApplication::STEPS.fetch(current_index + 1, step)
        application.update!(completed_steps: completed_steps, current_step: next_step)
      end

      application
    end
  end
end
