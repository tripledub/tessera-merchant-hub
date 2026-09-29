# frozen_string_literal: true

class AddFulfilmentDetailsToOnboardingApplications < ActiveRecord::Migration[8.0]
  def change
    change_table :onboarding_applications, bulk: true do |t|
      t.boolean :delivery_over_seven_days
      t.boolean :full_payment_before_delivery
      t.boolean :takes_deposits
      t.decimal :deposit_percentage, precision: 5, scale: 2
      t.string :remaining_balance_due
      t.text :service_requirements
      t.string :integration_type
    end
  end
end
