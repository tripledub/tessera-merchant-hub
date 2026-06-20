# frozen_string_literal: true

module ExtractionData
  class DeclarationOfTrust < Base
    register_as :declaration_of_trust

    attribute :trustee, :string
    attribute :beneficiary, :string
    attribute :declaration_date, :date
    attribute :trust_description, :string

    validates :trustee, :beneficiary, presence: true
  end
end
