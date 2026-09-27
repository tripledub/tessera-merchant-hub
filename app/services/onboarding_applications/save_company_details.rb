# frozen_string_literal: true

module OnboardingApplications
  class SaveCompanyDetails
    def self.call(application:, attributes:)
      saved = application.transaction do
        application.assign_attributes(attributes)
        next false unless application.save(context: :company)

        Advance.call(application: application, step: "company") if application.current_step == "company"
        true
      end

      saved
    end
  end
end
