# frozen_string_literal: true

module OnboardingApplications
  class SavePrincipals
    def self.call(application:, attributes:)
      attributes = attributes.to_h.deep_symbolize_keys
      principals = attributes.dig(:applicant_attributes, :kyc_principals_attributes) || {}
      principals.each_value do |principal|
        principal[:source] = :applicant_declared if principal[:id].blank?
      end

      SaveStepDetails.call(application: application, step: "principals", attributes: attributes)
    end
  end
end
