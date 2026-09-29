# frozen_string_literal: true

module OnboardingApplications
  class SaveDescriptorDetails
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "descriptor", attributes: attributes)
    end
  end
end
