# frozen_string_literal: true

module OnboardingApplications
  class SaveCurrencies
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "currencies", attributes: attributes)
    end
  end
end
