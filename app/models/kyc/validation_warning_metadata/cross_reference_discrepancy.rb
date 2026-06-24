# frozen_string_literal: true

module Kyc
  module ValidationWarningMetadata
    class CrossReferenceDiscrepancy
      include StoreModel::Model

      attribute :document_name, :string
      attribute :chart_percentage, :decimal
      attribute :document_percentage, :decimal
      attribute :discrepancy_type, :string
    end
  end
end
