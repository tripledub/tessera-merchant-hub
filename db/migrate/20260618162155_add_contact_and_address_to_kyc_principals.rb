class AddContactAndAddressToKycPrincipals < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_principals, :email, :string
    add_column :kyc_principals, :address_line1, :string
    add_column :kyc_principals, :address_line2, :string
    add_column :kyc_principals, :city, :string
    add_column :kyc_principals, :postcode, :string
    add_column :kyc_principals, :country, :string
  end
end
