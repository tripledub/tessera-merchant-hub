# frozen_string_literal: true

class AddProcessingHistoryToOnboardingApplications < ActiveRecord::Migration[8.0]
  def change
    change_table :onboarding_applications, bulk: true do |t|
      t.boolean :currently_accepts_card_payments
      t.string :current_acquirer
    end
  end
end
