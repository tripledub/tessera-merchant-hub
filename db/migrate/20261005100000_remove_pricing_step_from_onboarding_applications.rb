# frozen_string_literal: true

# The pricing step was an empty placeholder with no counterpart in the application
# form template, so it has been dropped from OnboardingApplication::STEPS. Move any
# application that references it so it still passes step validation.
class RemovePricingStepFromOnboardingApplications < ActiveRecord::Migration[8.0]
  def up
    remove_pricing_step
  end

  def down
    # Irreversible by design: the removed step carried no data.
  end

  def remove_pricing_step
    execute <<~SQL.squish
      UPDATE onboarding_applications
      SET current_step = CASE WHEN current_step = 'pricing' THEN 'volumes' ELSE current_step END,
          completed_steps = array_remove(completed_steps, 'pricing')
      WHERE current_step = 'pricing'
         OR 'pricing' = ANY(completed_steps)
    SQL
  end
end
