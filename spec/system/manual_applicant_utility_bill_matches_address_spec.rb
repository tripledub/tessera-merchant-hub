# frozen_string_literal: true

require "rails_helper"

# MH-320: real upload -> classify -> confirm -> extract journey for the new
# synthetic specimen utility bill fixtures (spec/fixtures/files), mirroring
# the passport specimens' precedent (MH-314). Extraction is stubbed with the
# ground truth already verified against the real Claude endpoint for each
# fixture — see spec/jobs/extract_kyc_document_job_spec.rb's matching
# contexts for how that ground truth was captured and what it means.
#
# The freshness boundary itself (AC2: exactly 3 months old is valid, one day
# older is stale) is covered separately in
# spec/requests/kyc/utility_bill_freshness_boundary_spec.rb, driving the real
# confirm-date endpoint rather than a native browser date-picker widget —
# this spec's job is proving the real upload/extraction/address-matching
# path, not re-testing that boundary arithmetic a second way.
RSpec.describe "Manual-filled applicant: utility bill matches an existing principal's address",
  qase_id: 15, type: :system do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  # Ground truth verified against the real Claude extraction endpoint for
  # specimen_utilitybill_address_formatting.pdf: the model normalizes the
  # printed "12 HIGH STREET LONDON SW1A1AA UNITED KINGDOM" (no commas, no
  # postcode space) back to the same clean fields as the tidy fixture's —
  # see extract_kyc_document_job_spec.rb's matching context for the full
  # explanation. Both fixtures therefore extract identically.
  let(:utility_bill_extraction) do
    {
      "full_name" => "Alex Testperson",
      "account_holder_address_line1" => "12 High Street",
      "account_holder_city" => "London",
      "account_holder_postcode" => "SW1A 1AA",
      "account_holder_country" => "United Kingdom",
      "provider" => "Utopia Power & Light",
      "provider_address" => "1 Substation Road, Utopia City, UT1 2AA, Republic of Utopia",
      "issue_date" => "2020-01-15",
      "account_number" => "UTL-0001-9284"
    }
  end

  before do
    # Mirrors config/kyc/policies/base.yml's base.utility_bill_freshness.
    # Not ambient in the test DB the way passport policies happen to be
    # locally — publish explicitly, same as
    # spec/services/kyc/document_validity/assessor_spec.rb and
    # spec/requests/kyc/utility_bill_freshness_boundary_spec.rb, so this
    # passes on a fresh test database (e.g. CI), not just a locally
    # pre-synced one.
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
      mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
    )
    allow(Kyc::DocumentExtractorService).to receive(:call).and_return(utility_bill_extraction)
    sign_in_via_form(psp_admin, password: "password123!")
  end

  # rubocop:disable RSpec/ExampleLength -- one linear real-browser journey,
  # see spec/system/manual_applicant_passport_creates_principal_spec.rb
  it "matches the utility bill to a principal whose stored address is identical, despite the bill's printed formatting differing" do
    visit new_applicant_path
    fill_in "applicant_name", with: "System Spec Utility Bill Co"
    click_button "Confirm & Create"
    applicant = Applicant.find_by!(name: "System Spec Utility Bill Co")

    # A principal must already exist with a stored address for the bill to
    # match against — utility bills don't auto-create principals the way a
    # passport does (PrincipalMatcherService: proof-of-address documents
    # never auto-create).
    principal = create(:kyc_principal, applicant: applicant, name: "Alex Testperson",
      address_line1: "12 High Street", city: "London", postcode: "SW1A 1AA", country: "United Kingdom")

    click_on "Documents"
    find("input[data-dropzone-target='input']", visible: false)
      .set(Rails.root.join("spec/fixtures/files/specimen_utilitybill_address_formatting.pdf"))
    click_button "Upload"
    expect(page).to have_css("[data-controller='classification']")
    perform_enqueued_jobs

    visit "#{applicant_path(applicant)}#documents"
    expect(page).to have_content(I18n.t("kyc.documents.document_types.utility_bill"))

    confirm_classification!
    run_extraction!

    visit "#{applicant_path(applicant)}#documents"
    expect(page).to have_content("Alex Testperson")
    expect(page).to have_content(I18n.t("kyc.documents.address_match_method.exact"))
    expect(page).to have_content(I18n.t("kyc.documents.validity.outcomes.confirmation_required"))

    document = applicant.kyc_documents.sole
    expect(document.address_match_method).to eq("exact")
    expect(document.kyc_principal).to eq(principal)
    expect(document.validity_confirmation_required).to be(true)
  end
  # rubocop:enable RSpec/ExampleLength
end
