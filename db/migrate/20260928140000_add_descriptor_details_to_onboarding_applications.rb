# frozen_string_literal: true

class AddDescriptorDetailsToOnboardingApplications < ActiveRecord::Migration[8.0]
  def change
    change_table :onboarding_applications, bulk: true do |t|
      t.string :descriptor
      t.string :descriptor_company_number
      t.string :descriptor_company_city
    end
  end
end
