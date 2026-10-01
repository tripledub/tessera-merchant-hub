# frozen_string_literal: true

# MH-382: record the outcome of an applicant's own registry lookup so the overview
# can tell "never attempted" from "failed" instead of inferring from registry_profiles.
class AddRegistryLookupStatusToMerchants < ActiveRecord::Migration[8.1]
  def up
    add_column :merchants, :registry_lookup_attempted_at, :datetime
    add_column :merchants, :registry_lookup_error, :string

    backfill_existing_applicants
  end

  def down
    remove_column :merchants, :registry_lookup_error
    remove_column :merchants, :registry_lookup_attempted_at
  end

  # Only a profile for the applicant's *own* company number proves its lookup succeeded;
  # profiles for other numbers are PSC-chain lookups. Everything else stays "never attempted".
  def backfill_existing_applicants
    execute <<~SQL.squish
      UPDATE merchants
      SET registry_lookup_attempted_at = own_profiles.last_fetched_at
      FROM (
        SELECT registry_profiles.applicant_id, MAX(registry_profiles.fetched_at) AS last_fetched_at
        FROM registry_profiles
        INNER JOIN merchants applicants ON applicants.id = registry_profiles.applicant_id
          AND applicants.company_number = registry_profiles.company_number
        GROUP BY registry_profiles.applicant_id
      ) own_profiles
      WHERE merchants.id = own_profiles.applicant_id
    SQL
  end
end
