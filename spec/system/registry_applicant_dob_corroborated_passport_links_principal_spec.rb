# frozen_string_literal: true

require "rails_helper"

# MH-303: full journey for the "agree" case — a registry-fetched principal
# who only has a partial (month/year) date of birth gets linked and
# backfilled when a later passport's full date of birth agrees, using the
# MH-310 synthetic Utopia registry's XU000002 scenario, whose officers were
# built specifically to match the synthetic specimen passports' month/year of
# birth (see config/synthetic/registry_scenarios.yml).
RSpec.describe "Registry-filled applicant: agreeing passport DOB corroborates and links a registry principal",
  type: :system do
  include_context "with synthetic data enabled"

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

  # rubocop:disable RSpec/ExampleLength -- one linear real-browser journey,
  # see spec/system/manual_applicant_passport_creates_principal_spec.rb
  it "links the passport to the matching registry director instead of creating a new principal" do
    visit new_applicant_path
    fill_in "applicant_name", with: "System Spec MH-303 Co"
    select "Utopia (test data)", from: "applicant_registry_jurisdiction"
    fill_in "applicant_company_number", with: "XU000002"
    click_button "Confirm & Create"

    applicant = Applicant.find_by!(name: "System Spec MH-303 Co")
    director = applicant.kyc_principals.find_by!(name: "TESTPERSON, Alex")
    expect(director.date_of_birth_month).to eq(3)
    expect(director.date_of_birth_year).to eq(1980)
    expect(director.date_of_birth).to be_nil

    click_on "Documents"
    find("input[data-dropzone-target='input']", visible: false)
      .set(Rails.root.join("spec/fixtures/files/specimen_passport_alex_testperson.pdf"))
    click_button "Upload"
    expect(page).to have_css("[data-controller='classification']")
    perform_enqueued_jobs

    visit "#{applicant_path(applicant)}#documents"
    confirm_classification!
    run_extraction!

    visit "#{applicant_path(applicant)}#documents"
    expect(page).to have_content(I18n.t("kyc.documents.match_method.registry_corroborated"))
    expect(page).not_to have_content(I18n.t("kyc.documents.principal_status.unconfirmed"))

    expect(applicant.kyc_principals.pluck(:name)).to contain_exactly("TESTPERSON, Alex", "EXAMPLESON, Morgan Lee")
    director.reload
    expect(director.date_of_birth).to eq(Date.new(1980, 3, 15))
    expect(director).to be_confirmed
  end
  # rubocop:enable RSpec/ExampleLength
end
