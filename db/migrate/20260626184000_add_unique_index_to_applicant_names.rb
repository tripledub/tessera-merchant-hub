# frozen_string_literal: true

class AddUniqueIndexToApplicantNames < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      WITH duplicate_applicants AS (
        SELECT
          id,
          ROW_NUMBER() OVER (PARTITION BY LOWER(name) ORDER BY created_at, id) AS duplicate_position
        FROM merchants
        WHERE type = 'Applicant'
      )
      UPDATE merchants
      SET
        name = CONCAT(merchants.name, ' (', SUBSTRING(merchants.id::text, 1, 8), ')'),
        updated_at = CURRENT_TIMESTAMP
      FROM duplicate_applicants
      WHERE merchants.id = duplicate_applicants.id
        AND duplicate_applicants.duplicate_position > 1
    SQL

    add_index :merchants,
      "LOWER(name)",
      unique: true,
      where: "type = 'Applicant'",
      name: "index_merchants_on_lower_applicant_name"
  end

  def down
    remove_index :merchants, name: "index_merchants_on_lower_applicant_name"
  end
end
