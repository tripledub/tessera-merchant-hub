# frozen_string_literal: true

module ExtractionData
  class WalletCustodyInfrastructureAttestation < Base
    register_as :wallet_custody_infrastructure_attestation

    attribute :provider_name, :string
    attribute :custody_description, :string
    attribute :storage_description, :string
  end
end
