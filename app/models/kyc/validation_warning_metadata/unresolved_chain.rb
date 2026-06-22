# frozen_string_literal: true

module Kyc
  module ValidationWarningMetadata
    class UnresolvedChain
      include StoreModel::Model

      attribute :entity_name, :string
    end
  end
end
