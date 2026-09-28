# frozen_string_literal: true

module OnboardingApplications
  class SaveDescriptorDetails
    def self.call(application:, attributes:)
      application.transaction do
        application.assign_attributes(attributes)
        next false unless application.save(context: :descriptor)

        Advance.call(application: application, step: "descriptor") if application.current_step == "descriptor"
        true
      end
    end
  end
end
