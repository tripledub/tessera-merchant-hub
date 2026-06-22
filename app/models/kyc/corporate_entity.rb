# frozen_string_literal: true

module Kyc
  class CorporateEntity < ApplicationRecord
    self.table_name = "kyc_corporate_entities"

    belongs_to :applicant
    belongs_to :kyc_document

    has_many :child_edges, class_name: "Kyc::OwnershipEdge", foreign_key: :parent_entity_id,
             dependent: :destroy, inverse_of: :parent_entity
    has_many :parent_edges, class_name: "Kyc::OwnershipEdge", foreign_key: :child_entity_id,
             dependent: :destroy, inverse_of: :child_entity
    has_many :validation_warnings, class_name: "Kyc::ValidationWarning",
             dependent: :nullify, inverse_of: :corporate_entity

    enum :entity_type, { individual: 0, corporate: 1 }

    validates :name, presence: true
    validates :entity_type, presence: true
  end
end
