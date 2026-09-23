# frozen_string_literal: true

require "rails_helper"

# MH-322: document row redesign. Confirm is the only direct action button,
# shown only when classification is unconfirmed; everything else lives
# behind a single overflow menu whose contents are state-driven, the same
# across all three MH-302 panels.
RSpec.describe "Documents tab row actions", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  let(:applicant) { create(:applicant) }

  before { sign_in psp_admin }

  def documents_tab
    get tab_applicant_path(applicant, tab: "documents")
    Nokogiri::HTML::DocumentFragment.parse(response.body)
  end

  def row_for(document)
    documents_tab.css("##{ActionView::RecordIdentifier.dom_id(document)}").first
  end

  it "shows the Confirm classification control only when classification is unconfirmed" do
    unconfirmed = create(:kyc_document, applicant: applicant, classification_status: :ai_suggested, document_type: :passport)
    confirmed = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)

    expect(row_for(unconfirmed).css("button[data-action='click->classification#confirm']")).not_to be_empty
    expect(row_for(confirmed).css("button[data-action='click->classification#confirm']")).to be_empty
  end

  it "offers retry from the overflow menu only for an errored document" do
    errored = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :error)
    processing = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :processing)

    retry_label = I18n.t("kyc.documents.retry")
    expect(row_for(errored).css("form button").map(&:text).map(&:strip)).to include(retry_label)
    expect(row_for(processing).css("form button").map(&:text).map(&:strip)).not_to include(retry_label)
  end

  it "always offers comments and delete from the overflow menu, regardless of state" do
    unconfirmed = create(:kyc_document, applicant: applicant, classification_status: :unclassified)
    processed = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

    [ unconfirmed, processed ].each do |document|
      row = row_for(document)
      expect(row.css("#comments-trigger-#{document.id}")).not_to be_empty
      expect(row.css("form[action='#{kyc_document_path(document)}'] button")).not_to be_empty
    end
  end

  it "offers the date-confirmation menu entry only when there are validity dates to confirm" do
    with_dates = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
           classification_status: :confirmed,
           validity_dates: { "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01",
             "confidence" => 0.95, "provenance" => "ai_extraction" } })
    without_dates = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

    expect(row_for(with_dates).to_s).to include(date_confirmation_modal_kyc_document_path(with_dates))
    expect(row_for(without_dates).to_s).not_to include("date_confirmation_modal")
  end

  it "renders a single overflow menu trigger per row, the same across Unconfirmed, Confirmed and Processed panels" do
    unconfirmed = create(:kyc_document, applicant: applicant, classification_status: :unclassified)
    confirmed = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
    processed = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

    [ unconfirmed, confirmed, processed ].each do |document|
      expect(row_for(document).css("[data-overflow-menu-target='button']").size).to eq(1)
    end
  end
end
