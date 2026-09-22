# frozen_string_literal: true

# MH-303: when a passport's name matches a registry-fetched principal but its
# extracted date of birth disagrees with that principal's registry month/year,
# PrincipalMatcherService blocks the auto-link (kyc_principal stays nil) and
# records the candidate here instead, so the document row can show the
# mismatch and a reviewer can resolve it (Kyc::PrincipalMatchOverrideService).
class AddDobMismatchKycPrincipalToKycDocuments < ActiveRecord::Migration[8.1]
  def change
    add_reference :kyc_documents, :dob_mismatch_kyc_principal, type: :uuid,
                   foreign_key: { to_table: :kyc_principals }, index: true
  end
end
