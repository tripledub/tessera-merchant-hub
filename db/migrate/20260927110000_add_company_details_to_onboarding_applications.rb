# frozen_string_literal: true

class AddCompanyDetailsToOnboardingApplications < ActiveRecord::Migration[8.0]
  def change
    change_table :onboarding_applications, bulk: true do |t|
      t.text :eu_entity_details
      t.string :referrer
      t.text :business_model_description
      t.text :test_login_details
      t.text :operating_licence
    end
  end
end
