# frozen_string_literal: true

class AddOwnershipPercentageToKycPrincipals < ActiveRecord::Migration[8.1]
  def change
    add_column :kyc_principals, :ownership_percentage, :decimal, precision: 5, scale: 2
  end
end
