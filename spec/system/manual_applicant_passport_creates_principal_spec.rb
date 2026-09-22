# frozen_string_literal: true

require "rails_helper"

# MH-314: automated counterpart of Qase case 1 ("Manual-filled applicant:
# passport creates principal with DOB", Qase project MH). Drives the real
# upload -> classify -> confirm -> extract flow in a browser; extraction
# itself is stubbed with the ground truth already verified against the real
# Claude endpoint for this fixture (see MH-309/MH-310 session notes), so the
# spec is fast and deterministic and exercises our app logic, not Claude's OCR.
RSpec.describe "Manual-filled applicant: passport creates principal with DOB", qase_id: 1, type: :system do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  let(:passport_extraction) do
    {
      "full_name" => "ALEX TESTPERSON",
      "date_of_birth" => "1980-03-15",
      "document_number" => "TEST00001",
      "expiry_date" => "2028-09-21",
      "issuing_country" => "Republic of Utopia",
      "nationality" => "Utopian",
      "issuing_authority" => "TEST AUTHORITY"
    }
  end

  before do
    allow(Kyc::DocumentExtractorService).to receive(:call).and_return(passport_extraction)
    sign_in_via_form(psp_admin, password: "password123!")
  end

  # rubocop:disable RSpec/ExampleLength -- one linear real-browser journey
  # (upload -> classify -> confirm -> extract -> verify); splitting it up
  # would just move shared browser state between examples, which Capybara
  # system specs don't support cleanly.
  it "creates an unconfirmed director principal with the extracted date of birth" do
    visit new_applicant_path
    fill_in "applicant_name", with: "System Spec Manual Co"
    click_button "Confirm & Create"

    expect(page).to have_content("System Spec Manual Co")
    applicant = Applicant.find_by!(name: "System Spec Manual Co")

    click_on "Documents"
    find("input[data-dropzone-target='input']", visible: false)
      .set(Rails.root.join("spec/fixtures/files/specimen_passport_alex_testperson.pdf"))
    click_button "Upload"
    expect(page).to have_css("[data-controller='classification']")
    perform_enqueued_jobs

    visit "#{applicant_path(applicant)}#documents"
    expect(page).to have_content(I18n.t("kyc.documents.classification.status.auto_classified"))

    confirm_classification!
    run_extraction!

    visit "#{applicant_path(applicant)}#documents"
    expect(page).to have_content("ALEX TESTPERSON")
    expect(page).to have_content(I18n.t("kyc.documents.principal_status.unconfirmed"))

    principal = applicant.kyc_principals.sole
    expect(principal.name).to eq("ALEX TESTPERSON")
    expect(principal.date_of_birth).to eq(Date.new(1980, 3, 15))
    expect(principal).to be_director
    expect(principal).to be_unconfirmed
    expect(principal).to be_document_extracted

    click_on "Principals"
    click_link "ALEX TESTPERSON"
    expect(page).to have_content("15 March 1980")
  end
  # rubocop:enable RSpec/ExampleLength
end
