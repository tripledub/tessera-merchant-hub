# frozen_string_literal: true

require "rails_helper"

# MH-314: automated counterpart of Qase case 4 ("Registry-filled applicant:
# passport for a person not on the registry creates a new principal", Qase
# project MH). Uses the MH-310 synthetic Utopia registry (XU000001, two
# officers who do not match the uploaded passport's name) instead of a real
# Companies House company. Extraction is stubbed with the ground truth
# already verified against the real Claude endpoint for this fixture.
RSpec.describe "Registry-filled applicant: unmatched passport creates a new principal",
  qase_id: 4, type: :system do
  include_context "with synthetic data enabled"

  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  let(:passport_extraction) do
    {
      "full_name" => "Morgan Lee Exampleson",
      "date_of_birth" => "1991-11-02",
      "document_number" => "TEST00002",
      "expiry_date" => "2028-09-21",
      "issuing_country" => "Republic of Utopia",
      "nationality" => "Utopian",
      "issuing_authority" => "Test Authority"
    }
  end

  before do
    allow(Kyc::DocumentExtractorService).to receive(:call).and_return(passport_extraction)
    sign_in_via_form(psp_admin, password: "password123!")
  end

  # rubocop:disable RSpec/ExampleLength -- one linear real-browser journey,
  # see spec/system/manual_applicant_passport_creates_principal_spec.rb
  it "leaves the registry directors untouched and creates a new unconfirmed principal from the passport" do
    visit new_applicant_path
    fill_in "applicant_name", with: "System Spec Registry Co"
    select "Utopia (test data)", from: "applicant_registry_jurisdiction"
    fill_in "applicant_company_number", with: "XU000001"
    click_button "Confirm & Create"

    applicant = Applicant.find_by!(name: "System Spec Registry Co")
    expect(applicant.kyc_principals.pluck(:name)).to contain_exactly("SAMPLE, Riley", "EXAMPLE, Jordan")

    click_on "Documents"
    find("input[data-dropzone-target='input']", visible: false)
      .set(Rails.root.join("spec/fixtures/files/specimen_passport_morgan_exampleson.pdf"))
    click_button "Upload"
    expect(page).to have_css("[data-controller='classification']")
    perform_enqueued_jobs

    visit "#{applicant_path(applicant)}#documents"
    confirm_classification!
    run_extraction!

    visit "#{applicant_path(applicant)}#documents"
    expect(page).to have_content("Morgan Lee Exampleson")
    expect(page).to have_content(I18n.t("kyc.documents.principal_status.unconfirmed"))

    expect(applicant.kyc_principals.pluck(:name)).to contain_exactly(
      "SAMPLE, Riley", "EXAMPLE, Jordan", "Morgan Lee Exampleson"
    )
    new_principal = applicant.kyc_principals.find_by!(name: "Morgan Lee Exampleson")
    expect(new_principal.date_of_birth).to eq(Date.new(1991, 11, 2))
    expect(new_principal).to be_unconfirmed
    expect(new_principal).to be_document_extracted
  end
  # rubocop:enable RSpec/ExampleLength
end
