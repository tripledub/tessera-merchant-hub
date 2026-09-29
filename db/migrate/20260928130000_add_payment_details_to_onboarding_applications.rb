# frozen_string_literal: true

class AddPaymentDetailsToOnboardingApplications < ActiveRecord::Migration[8.0]
  STEPS_AFTER_PAYMENTS = %w[pricing volumes countries principals review].freeze

  def up
    change_table :onboarding_applications, bulk: true do |t|
      t.boolean :uses_shopping_cart
      t.string :shopping_cart_provider
      t.boolean :takes_recurring_payments
      t.boolean :sends_recurring_payment_receipts
      t.boolean :sends_recurring_payment_advance_notifications
    end

    backfill_existing_drafts
  end

  def down
    execute <<~SQL.squish
      UPDATE onboarding_applications
      SET current_step = CASE WHEN current_step = 'payments' THEN 'pricing' ELSE current_step END,
          completed_steps = array_remove(completed_steps, 'payments')
      WHERE current_step = 'payments'
         OR 'payments' = ANY(completed_steps)
    SQL

    remove_columns :onboarding_applications,
                   :uses_shopping_cart,
                   :shopping_cart_provider,
                   :takes_recurring_payments,
                   :sends_recurring_payment_receipts,
                   :sends_recurring_payment_advance_notifications
  end

  def backfill_existing_drafts
    quoted_steps = STEPS_AFTER_PAYMENTS.map { |step| connection.quote(step) }.join(", ")
    execute <<~SQL.squish
      UPDATE onboarding_applications
      SET current_step = 'payments'
      WHERE status = 0
        AND current_step IN (#{quoted_steps})
    SQL
  end
end
