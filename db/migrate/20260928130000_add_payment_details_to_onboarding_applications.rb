# frozen_string_literal: true

class AddPaymentDetailsToOnboardingApplications < ActiveRecord::Migration[8.0]
  def change
    change_table :onboarding_applications, bulk: true do |t|
      t.boolean :uses_shopping_cart
      t.string :shopping_cart_provider
      t.boolean :takes_recurring_payments
      t.boolean :sends_recurring_payment_receipts
      t.boolean :sends_recurring_payment_advance_notifications
    end
  end
end
