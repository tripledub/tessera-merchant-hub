# frozen_string_literal: true

require "rails_helper"

# MH-422: after an upload the chat says what became of the file, without a reload.
# The job's broadcast reaches the open page through the in-process cable.
RSpec.describe "Chat: the outcome of an upload", type: :system do
  include ActiveJob::TestHelper

  let(:applicant) { create(:applicant, company_name: "Acme Widgets") }
  let!(:applicant_user) { create(:applicant_user, applicant: applicant) }
  let(:checklist) do
    [ { "category" => "corporate", "subject" => "company", "document_types" => %w[certificate_of_incorporation],
        "label" => "Certificate of incorporation", "deferred" => false },
      { "category" => "proof_of_business_address", "subject" => "company",
        "document_types" => Kyc::DocumentCategory.types_for(:proof_of_business_address),
        "label" => "Proof of business address", "deferred" => false } ]
  end
  let!(:onboarding_session) do
    create(:onboarding_session, applicant: applicant, current_stage: :document_collection, document_checklist: checklist,
                                stage_data: { "company_info" => { "company_name" => "Acme Widgets" } })
  end

  before do
    create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "Please upload your documents.")
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_onboarding_path
  end

  def upload(filename_on_disk)
    # The file input sits in a hidden form the + button opens; show it so the driver can fill it in.
    page.execute_script("document.getElementById('onboarding_document_upload').form.classList.remove('hidden')")
    attach_file "onboarding_document_upload", Rails.root.join("spec/fixtures/files", filename_on_disk), make_visible: true
    expect(page).to have_text("processing now")
  end

  it "tells the applicant a recognised document is recognised and under review, and refreshes the checklist" do
    upload("sample.pdf")
    allow(DocumentClassifiers).to receive(:obtain).and_return(
      instance_double(DocumentClassifiers::Base, classify: { document_type: "certificate_of_incorporation", confidence: 1.0,
                                                             classification_method: :rule_based })
    )
    expect(page).to have_css("#onboarding_document_checklist", text: "Certificate of incorporation")

    perform_enqueued_jobs(only: ClassifyKycDocumentJob)

    expect(page).to have_css(".kyn-bubble-assistant", text: "I've recognised your Certificate of Incorporation and it's under review.")
    expect(page).to have_no_css("#onboarding_document_checklist", text: "Certificate of incorporation")
  end

  it "tells the applicant when a file could not be recognised, and ends with a message, not 'processing'" do
    upload("sample.pdf")
    allow(DocumentClassifiers).to receive(:obtain).and_return(
      instance_double(DocumentClassifiers::Base, classify: { document_type: nil, confidence: nil,
                                                             classification_method: :ai })
    )

    perform_enqueued_jobs(only: ClassifyKycDocumentJob)

    expect(page).to have_text("I couldn't tell what “sample.pdf” is.")
  end

  it "tells the applicant when a file could not be read" do
    upload("sample.pdf")
    allow(DocumentClassifiers).to receive(:obtain).and_raise(Faraday::TimeoutError, "slow")
    allow(Honeybadger).to receive(:notify)

    perform_enqueued_jobs(only: ClassifyKycDocumentJob)

    expect(page).to have_text("I couldn't read “sample.pdf”.")
    expect(KycDocument.last.status).to eq("error")
  end

  it "shows the same messages, once each, after a reload" do
    upload("sample.pdf")
    allow(DocumentClassifiers).to receive(:obtain).and_raise(Faraday::TimeoutError, "slow")
    allow(Honeybadger).to receive(:notify)
    perform_enqueued_jobs(only: ClassifyKycDocumentJob)

    page.driver.refresh

    expect(page).to have_text("I couldn't read “sample.pdf”.", count: 1)
  end
end
