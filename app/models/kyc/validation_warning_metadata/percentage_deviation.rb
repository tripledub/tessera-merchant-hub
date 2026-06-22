# frozen_string_literal: true

module Kyc
  module ValidationWarningMetadata
    class PercentageDeviation
      include StoreModel::Model

      attribute :expected, :decimal
      attribute :actual, :decimal
      attribute :deviation, :decimal
    end
  end
end
