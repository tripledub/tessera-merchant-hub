# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261005120000_create_onboarding_countries")

RSpec.describe CreateOnboardingCountries do
  it "routes drafts already past the countries step back through it" do
    principals_draft = create(:onboarding_application, current_step: "principals")
    review_draft = create(:onboarding_application, current_step: "review")
    earlier_draft = create(:onboarding_application, current_step: "payments")
    submitted = create(:onboarding_application, current_step: "review", status: :submitted)

    described_class.new.route_drafts_through_countries

    expect(principals_draft.reload.current_step).to eq("countries")
    expect(review_draft.reload.current_step).to eq("countries")
    expect(earlier_draft.reload.current_step).to eq("payments")
    expect(submitted.reload.current_step).to eq("review")
  end
end
