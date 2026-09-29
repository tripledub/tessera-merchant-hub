# frozen_string_literal: true

module OnboardingApplications
  class SavePaymentDetails
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "payments", attributes: attributes)
    end
  end
end
