# frozen_string_literal: true

# MH-331: a staff-triggered principal merge soft-deletes the losing row by
# pointing it at the surviving row instead of destroying it, so the merged
# row's original field values stay in the DB rather than being lost.
class AddMergedIntoIdToKycPrincipals < ActiveRecord::Migration[8.1]
  def change
    add_reference :kyc_principals, :merged_into, type: :uuid,
                   foreign_key: { to_table: :kyc_principals }, index: true
  end
end
