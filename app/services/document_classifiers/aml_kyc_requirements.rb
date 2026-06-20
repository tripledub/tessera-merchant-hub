# frozen_string_literal: true

module DocumentClassifiers
  class AmlKycRequirements < Base
    register handler: :aml_kyc_requirements

    def self.pattern
      /aml.kyc\s*requirements?|kyc\s*requirements?/i
    end
  end
end
