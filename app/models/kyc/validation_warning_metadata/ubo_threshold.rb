# frozen_string_literal: true

module Kyc
  module ValidationWarningMetadata
    class UboThreshold
      include StoreModel::Model

      attribute :individual_name, :string
      attribute :effective_percentage, :decimal
      attribute :threshold, :decimal
    end
  end
end
