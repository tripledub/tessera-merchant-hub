# frozen_string_literal: true

module Kyc
  module ValidationWarningMetadata
    class NomineeDetected
      include StoreModel::Model

      attribute :detection_reason, :string
      attribute :jurisdiction, :string
    end
  end
end
