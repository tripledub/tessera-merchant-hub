# frozen_string_literal: true

module ExtractionData
  class AmlCtfPolicy < Base
    register_as :aml_ctf_policy

    attribute :entity_name, :string
    attribute :policy_date, :date
    attribute :version, :string
    attribute :mlro_name, :string

    validates :entity_name, presence: true
  end
end
