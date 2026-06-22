# frozen_string_literal: true

module Kyc
  class ValidationWarning < ApplicationRecord
    self.table_name = "kyc_validation_warnings"

    belongs_to :applicant
    belongs_to :kyc_document
    belongs_to :corporate_entity, class_name: "Kyc::CorporateEntity", optional: true

    enum :warning_type, { percentage_deviation: 0, nominee_detected: 1, unresolved_chain: 2, ubo_threshold_exceeded: 3 }

    validates :warning_type, presence: true
    validates :message, presence: true

    METADATA_TYPES = {
      "percentage_deviation" => Kyc::ValidationWarningMetadata::PercentageDeviation,
      "nominee_detected" => Kyc::ValidationWarningMetadata::NomineeDetected,
      "unresolved_chain" => Kyc::ValidationWarningMetadata::UnresolvedChain,
      "ubo_threshold_exceeded" => Kyc::ValidationWarningMetadata::UboThreshold
    }.freeze

    def typed_metadata
      klass = METADATA_TYPES[warning_type]
      return metadata unless klass

      klass.new(metadata || {})
    end
  end
end
