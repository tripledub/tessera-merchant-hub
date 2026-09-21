# frozen_string_literal: true

require "rails_helper"

# MH-301: "Unlinked" means "the matcher tried and failed to attach this document
# to a person", so it only makes sense for the types the matcher can link.
RSpec.describe "Documents tab 'Unlinked' label", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  let(:applicant) { create(:applicant) }
  let(:label) { I18n.t("kyc.documents.unlinked") }

  before { sign_in psp_admin }

  def completed_document(type, **attrs)
    create(:kyc_document, applicant: applicant, document_type: type,
           classification_status: :confirmed, status: :complete, **attrs)
  end

  def documents_tab
    get tab_applicant_path(applicant, tab: "documents")
    response.body
  end

  %w[passport driving_licence utility_bill bank_account_statement].each do |type|
    it "still shows the label on a completed #{type} with no principal" do
      document = completed_document(type)

      body = documents_tab

      expect(body).to include(ActionView::RecordIdentifier.dom_id(document))
      expect(body).to include(label)
    end
  end

  %w[
    proof_of_domain_ownership processing_statement register_of_members share_certificate
    certificate_of_incorporation certificate_of_incumbency certificate_of_registered_address other
  ].each do |type|
    it "does not show the label on a completed #{type}, but still renders the row" do
      document = completed_document(type)

      body = documents_tab

      expect(body).to include(ActionView::RecordIdentifier.dom_id(document))
      expect(body).not_to include(label)
    end
  end

  it "does not show the label on a completed document with no type" do
    completed_document(nil)

    expect(documents_tab).not_to include(label)
  end

  it "shows the principal, not the label, once a linkable document is linked" do
    principal = create(:kyc_principal, applicant: applicant, name: "Jane Smith")
    completed_document("passport", kyc_principal: principal)

    body = documents_tab

    expect(body).to include("Jane Smith")
    expect(body).not_to include(label)
  end

  it "still shows no label on a linkable document that has not completed extraction" do
    create(:kyc_document, applicant: applicant, document_type: :passport,
           classification_status: :confirmed, status: :pending)

    expect(documents_tab).not_to include(label)
  end

  it "shows the label only on the linkable one when both kinds are on the page" do
    completed_document("passport")
    completed_document("proof_of_domain_ownership")

    expect(documents_tab.scan(label).size).to eq(1)
  end
end
