# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260928130000_add_payment_details_to_onboarding_applications")

RSpec.describe AddPaymentDetailsToOnboardingApplications do
  it "routes existing drafts beyond processing through the new payments step" do
    volumes_draft = create(:onboarding_application, current_step: "volumes")
    review_draft = create(:onboarding_application, current_step: "review")
    processing_draft = create(:onboarding_application, current_step: "processing")
    submitted_application = create(:onboarding_application, current_step: "volumes", status: :submitted)

    described_class.new.backfill_existing_drafts

    expect(volumes_draft.reload.current_step).to eq("payments")
    expect(review_draft.reload.current_step).to eq("payments")
    expect(processing_draft.reload.current_step).to eq("processing")
    expect(submitted_application.reload.current_step).to eq("volumes")
  end
end
