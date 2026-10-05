# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261005100000_remove_pricing_step_from_onboarding_applications")

RSpec.describe RemovePricingStepFromOnboardingApplications do
  def build_on_pricing(**attrs)
    application = create(:onboarding_application, **attrs)
    application.update_columns(current_step: "pricing", completed_steps: %w[company descriptor pricing])
    application
  end

  it "moves applications sitting on the removed pricing step to volumes and drops it from completed steps" do
    draft = build_on_pricing
    submitted = build_on_pricing(status: :submitted)
    other = create(:onboarding_application, current_step: "processing", completed_steps: %w[company])

    described_class.new.remove_pricing_step

    expect(draft.reload).to have_attributes(current_step: "volumes", completed_steps: %w[company descriptor])
    expect(submitted.reload).to have_attributes(current_step: "volumes", completed_steps: %w[company descriptor])
    expect(other.reload).to have_attributes(current_step: "processing", completed_steps: %w[company])
  end
end
