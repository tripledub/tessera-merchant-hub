# frozen_string_literal: true

module OnboardingApplications
  class SavePaymentDetails
    def self.call(application:, attributes:)
      application.transaction do
        application.assign_attributes(attributes)
        next false unless application.save(context: :payments)

        Advance.call(application: application, step: "payments") if application.current_step == "payments"
        true
      end
    end
  end
end
