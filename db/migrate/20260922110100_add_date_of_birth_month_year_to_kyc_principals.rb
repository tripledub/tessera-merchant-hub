# frozen_string_literal: true

# MH-303: carries the registry-published month/year of birth onto the
# principal itself, so PrincipalMatcherService can corroborate (or flag a
# mismatch against) a later-uploaded passport's full date of birth. `date_of_birth`
# stays the single source of truth once known in full; these two columns hold
# the partial value until then.
class AddDateOfBirthMonthYearToKycPrincipals < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_principals, :date_of_birth_month, :integer
    add_column :kyc_principals, :date_of_birth_year, :integer
  end
end
