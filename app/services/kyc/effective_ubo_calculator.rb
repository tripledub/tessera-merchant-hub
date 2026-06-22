# frozen_string_literal: true

module Kyc
  class EffectiveUboCalculator
    UBO_THRESHOLD = 25.0

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
      @applicant = document.applicant
    end

    def call
      results = compute_effective_ownership
      results.each do |row|
        next if row["effective_percentage"].to_f < UBO_THRESHOLD

        entity = Kyc::CorporateEntity.find(row["individual_id"])
        target = Kyc::CorporateEntity.find(row["target_id"])

        Kyc::ValidationWarning.create!(
          applicant: @applicant,
          kyc_document: @document,
          corporate_entity: entity,
          warning_type: :ubo_threshold_exceeded,
          message: "UBO identified: #{entity.name} has #{row['effective_percentage'].to_f.round(2)}% effective ownership of #{target.name}",
          metadata: {
            individual_name: entity.name,
            effective_percentage: row["effective_percentage"].to_f.round(2),
            threshold: UBO_THRESHOLD
          }
        )
      end
    end

    private

    def compute_effective_ownership
      return [] unless Kyc::CorporateEntity.where(kyc_document: @document).exists?

      document_id = @document.id

      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, document_id ])
        WITH RECURSIVE ownership_paths AS (
          -- Base case: direct equity edges from individuals
          SELECT
            e.parent_entity_id AS individual_id,
            e.child_entity_id AS target_id,
            e.percentage::numeric AS effective_percentage,
            ARRAY[e.parent_entity_id, e.child_entity_id] AS path
          FROM kyc_ownership_edges e
          JOIN kyc_corporate_entities p ON p.id = e.parent_entity_id
          WHERE e.relationship_type = 0
            AND p.entity_type = 0
            AND p.kyc_document_id = ?

          UNION ALL

          -- Recursive case: extend path through corporate entities
          SELECT
            op.individual_id,
            e.child_entity_id AS target_id,
            op.effective_percentage * e.percentage / 100.0 AS effective_percentage,
            op.path || e.child_entity_id
          FROM ownership_paths op
          JOIN kyc_ownership_edges e ON e.parent_entity_id = op.target_id
          JOIN kyc_corporate_entities c ON c.id = op.target_id
          WHERE e.relationship_type = 0
            AND c.entity_type = 1
            AND NOT (e.child_entity_id = ANY(op.path))
        )
        SELECT
          individual_id,
          target_id,
          SUM(effective_percentage) AS effective_percentage
        FROM ownership_paths
        WHERE target_id != individual_id
        GROUP BY individual_id, target_id
      SQL

      ActiveRecord::Base.connection.exec_query(sql).to_a
    end
  end
end
