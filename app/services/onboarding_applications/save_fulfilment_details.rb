# frozen_string_literal: true

module OnboardingApplications
  class SaveFulfilmentDetails
    def self.call(application:, attributes:)
      application.transaction do
        application.assign_attributes(attributes)
        next false unless application.save(context: :fulfilment)

        Advance.call(application: application, step: "fulfilment") if application.current_step == "fulfilment"
        true
      end
    end
  end
end
