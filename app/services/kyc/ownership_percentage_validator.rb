# frozen_string_literal: true

module Kyc
  class OwnershipPercentageValidator
    TOLERANCE = 0.5

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
    end

    def call
      entities = Kyc::CorporateEntity.where(kyc_document: @document)

      entities.find_each do |entity|
        equity_edges = Kyc::OwnershipEdge.where(child_entity: entity, relationship_type: :equity)
        next if equity_edges.none?

        total = equity_edges.sum(:percentage)
        deviation = (total - 100.0).abs

        next if deviation <= TOLERANCE

        Kyc::ValidationWarning.create!(
          applicant: @applicant,
          kyc_document: @document,
          corporate_entity: entity,
          warning_type: :percentage_deviation,
          message: "Ownership of #{entity.name} sums to #{total}% (expected 100%)",
          metadata: { expected: 100.0, actual: total.to_f, deviation: deviation.to_f }
        )
      end
    end
  end
end
