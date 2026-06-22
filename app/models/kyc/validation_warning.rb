# frozen_string_literal: true

module Kyc
  class ValidationWarning < ApplicationRecord
    self.table_name = "kyc_validation_warnings"

    belongs_to :applicant
    belongs_to :kyc_document
    belongs_to :corporate_entity, class_name: "Kyc::CorporateEntity", optional: true

    enum :warning_type, { percentage_deviation: 0 }

    attribute :metadata, Kyc::ValidationWarningMetadata::PercentageDeviation.to_type

    validates :warning_type, presence: true
    validates :message, presence: true
  end
end
