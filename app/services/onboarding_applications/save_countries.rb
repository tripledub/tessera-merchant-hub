# frozen_string_literal: true

module OnboardingApplications
  class SaveCountries
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "countries", attributes: attributes)
    end
  end
end
