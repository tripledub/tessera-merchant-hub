# frozen_string_literal: true

module Kyc
  class EffectivePolicy
    def self.for(applicant)
      Kyc::PolicyRegistry.requirements_for(applicant.sector)
    end
  end
end
