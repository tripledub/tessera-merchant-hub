# frozen_string_literal: true

module Kyc
  class OwnershipEdge < ApplicationRecord
    self.table_name = "kyc_ownership_edges"

    belongs_to :parent_entity, class_name: "Kyc::CorporateEntity", inverse_of: :child_edges
    belongs_to :child_entity, class_name: "Kyc::CorporateEntity", inverse_of: :parent_edges
    belongs_to :source_document, class_name: "KycDocument", optional: true

    enum :relationship_type, { equity: 0, nominee: 1, contractual: 2 }

    validates :relationship_type, presence: true
  end
end
