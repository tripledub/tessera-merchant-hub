# frozen_string_literal: true

module OnboardingApplications
  class SaveProcessingHistory
    def self.call(application:, attributes:)
      application.transaction do
        application.assign_attributes(attributes)
        next false unless application.save(context: :processing)

        Advance.call(application: application, step: "processing") if application.current_step == "processing"
        true
      end
    end
  end
end
