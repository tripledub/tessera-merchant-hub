# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261001160000_add_registry_lookup_status_to_merchants")

RSpec.describe AddRegistryLookupStatusToMerchants do
  let(:fetched_at) { Time.utc(2026, 9, 1, 12, 0, 0) }

  it "marks an applicant as succeeded when a profile exists for its own company number" do
    applicant = create(:applicant, company_number: "12345678")
    create(:registry_profile, applicant: applicant, company_number: "12345678", fetched_at: fetched_at)

    described_class.new.backfill_existing_applicants

    expect(applicant.reload).to have_attributes(registry_lookup_attempted_at: fetched_at, registry_lookup_error: nil)
  end

  it "does not count a profile for a different company number (PSC chain)" do
    applicant = create(:applicant, company_number: "12345678")
    create(:registry_profile, applicant: applicant, company_number: "87654321", fetched_at: fetched_at)

    described_class.new.backfill_existing_applicants

    expect(applicant.reload.registry_lookup_attempted_at).to be_nil
  end

  it "leaves an applicant with no profile as never attempted" do
    applicant = create(:applicant, company_number: "12345678")

    described_class.new.backfill_existing_applicants

    expect(applicant.reload).to have_attributes(registry_lookup_attempted_at: nil, registry_lookup_error: nil)
  end
end
