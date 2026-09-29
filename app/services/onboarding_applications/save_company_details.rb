# frozen_string_literal: true

module OnboardingApplications
  class SaveCompanyDetails
    def self.call(application:, attributes:)
      saved = application.transaction do
        application.assign_attributes(attributes)
        application.save(context: :company)
      end

      return false unless saved

      Advance.call(application: application, step: "company") if application.current_step == "company"
      true
    rescue Advance::StepConflict
      application.reload
      true
    end
  end
end
