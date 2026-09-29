# frozen_string_literal: true

module OnboardingApplications
  class SaveProcessingHistory
    def self.call(application:, attributes:)
      SaveStepDetails.call(application: application, step: "processing", attributes: attributes)
    end
  end
end
