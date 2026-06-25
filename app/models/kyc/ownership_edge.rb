# frozen_string_literal: true

module Kyc
  class OwnershipEdge < ApplicationRecord
    self.table_name = "kyc_ownership_edges"

    belongs_to :parent_entity, class_name: "Kyc::CorporateEntity", inverse_of: :child_edges
    belongs_to :child_entity, class_name: "Kyc::CorporateEntity", inverse_of: :parent_edges
    belongs_to :source_document, class_name: "KycDocument", optional: true

    enum :relationship_type, { equity: 0, nominee: 1, contractual: 2 }
    enum :source, { document_extracted: 0, applicant_declared: 1 }, default: :document_extracted

    validates :relationship_type, presence: true
  end
end
