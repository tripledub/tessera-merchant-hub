# frozen_string_literal: true

module ExtractionData
  class AmlKycRequirements < Base
    register_as :aml_kyc_requirements

    attribute :entity_name, :string
    attribute :requirements_summary, :string
    attribute :issue_date, :date
  end
end
