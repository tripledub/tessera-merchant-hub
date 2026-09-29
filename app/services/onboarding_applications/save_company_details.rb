# frozen_string_literal: true

module OnboardingApplications
  class SaveCompanyDetails
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "company", attributes: attributes)
    end
  end
end
