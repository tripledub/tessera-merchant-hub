class AddDateOfBirthAndStatusToKycPrincipals < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_principals, :date_of_birth, :date
    add_column :kyc_principals, :status, :integer, null: false, default: 1
  end
end
