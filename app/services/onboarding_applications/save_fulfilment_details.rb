# frozen_string_literal: true

module OnboardingApplications
  class SaveFulfilmentDetails
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "fulfilment", attributes: attributes)
    end
  end
end
