# frozen_string_literal: true

module OnboardingApplications
  class FindOrCreate
    def self.call(applicant:)
      applicant.onboarding_application || applicant.create_onboarding_application!
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      applicant.reload.onboarding_application || raise
    end
  end
end
