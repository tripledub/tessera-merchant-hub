# frozen_string_literal: true

module OnboardingApplications
  class SaveCurrencies
    def self.call(application:, attributes:)
      application.transaction do
        application.assign_attributes(attributes)
        next false unless application.save(context: :currencies)

        Advance.call(application: application, step: "currencies") if application.current_step == "currencies"
        true
      end
    end
  end
end
