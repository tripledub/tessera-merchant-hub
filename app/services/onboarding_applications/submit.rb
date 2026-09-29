# frozen_string_literal: true

module OnboardingApplications
  class Submit
    def self.call(application:)
      application.transaction do
        application.lock!
        raise Advance::StepConflict unless application.current_step == "review"
        return false unless application.valid?(:submission)

        application.status = :submitted
        application.submitted_at = Time.current
        application.save!(context: :submission)
      end

      true
    end
  end
end
