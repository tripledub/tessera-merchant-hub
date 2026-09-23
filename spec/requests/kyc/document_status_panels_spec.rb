# frozen_string_literal: true

require "rails_helper"

# MH-302: the Documents tab splits into three panels around the upload
# dropzone — Unconfirmed Files, Confirmed Files, Processed Files — instead of
# one flat list.
RSpec.describe "Documents tab status panels", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  let(:applicant) { create(:applicant) }

  before { sign_in psp_admin }

  def documents_tab
    get tab_applicant_path(applicant, tab: "documents")
    response.body
  end

  def dom_id(document)
    ActionView::RecordIdentifier.dom_id(document)
  end

  # Slices the body from this panel's opening tag up to (not including) the
  # next panel's opening tag, so "not_to include" assertions can't accidentally
  # match content that legitimately belongs to a later panel.
  def panel_body(body, panel_id)
    start_index = body.index(%(id="#{panel_id}"))
    return "" unless start_index

    # Match only the next PANEL-level id (id="documents-panel-confirmed"), not a
    # panel's own child list div (id="documents-panel-confirmed-list").
    next_index = body.index(/id="documents-panel-(unconfirmed|confirmed|processed)"/, start_index + panel_id.length + 1)
    next_index ? body[start_index...next_index] : body[start_index..]
  end

  %w[unclassified auto_classified ai_suggested rejected].each do |classification|
    it "puts a #{classification} document in the Unconfirmed Files panel regardless of extraction status" do
      document = create(:kyc_document, applicant: applicant, classification_status: classification, status: :complete)

      body = documents_tab

      expect(panel_body(body, "documents-panel-unconfirmed")).to include(dom_id(document))
      expect(panel_body(body, "documents-panel-confirmed")).not_to include(dom_id(document))
      expect(panel_body(body, "documents-panel-processed")).not_to include(dom_id(document))
    end
  end

  %w[pending processing error].each do |status|
    it "puts a confirmed document with status #{status} in the Confirmed Files panel" do
      document = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: status)

      body = documents_tab

      expect(panel_body(body, "documents-panel-confirmed")).to include(dom_id(document))
      expect(panel_body(body, "documents-panel-unconfirmed")).not_to include(dom_id(document))
      expect(panel_body(body, "documents-panel-processed")).not_to include(dom_id(document))
    end
  end

  it "puts a confirmed, complete document in the Processed Files panel" do
    document = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

    body = documents_tab

    expect(panel_body(body, "documents-panel-processed")).to include(dom_id(document))
    expect(panel_body(body, "documents-panel-unconfirmed")).not_to include(dom_id(document))
    expect(panel_body(body, "documents-panel-confirmed")).not_to include(dom_id(document))
  end

  it "renders the panels top to bottom: Unconfirmed, dropzone, Confirmed, Processed" do
    create(:kyc_document, applicant: applicant, classification_status: :unclassified)
    create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
    create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

    body = documents_tab

    positions = {
      unconfirmed: body.index('id="documents-panel-unconfirmed"'),
      dropzone: body.index('id="kyc-upload"'),
      confirmed: body.index('id="documents-panel-confirmed"'),
      processed: body.index('id="documents-panel-processed"')
    }

    expect(positions.values).to all(be_present)
    expect(positions[:unconfirmed]).to be < positions[:dropzone]
    expect(positions[:dropzone]).to be < positions[:confirmed]
    expect(positions[:confirmed]).to be < positions[:processed]
  end

  it "hides a panel with zero documents and shows one with at least one" do
    create(:kyc_document, applicant: applicant, classification_status: :unclassified)

    body = documents_tab

    expect(panel_body(body, "documents-panel-unconfirmed")[0...300]).not_to include("hidden")
    expect(panel_body(body, "documents-panel-confirmed")[0...300]).to include("hidden")
    expect(panel_body(body, "documents-panel-processed")[0...300]).to include("hidden")
  end

  it "shows a count alongside each non-empty panel's label" do
    create_list(:kyc_document, 2, applicant: applicant, classification_status: :unclassified)

    body = documents_tab
    unconfirmed_panel = panel_body(body, "documents-panel-unconfirmed")

    expect(unconfirmed_panel).to include("Unconfirmed Files")
    expect(unconfirmed_panel[0...300]).to include("(2)")
  end

  it "never blocks uploading while documents sit in Unconfirmed Files" do
    create(:kyc_document, applicant: applicant, classification_status: :unclassified)

    body = documents_tab
    upload_start = body.index('id="kyc-upload"')
    upload_section = body[upload_start...body.index('id="documents-panel-confirmed"')]

    expect(upload_section).to include(I18n.t("applicants.show.documents.upload_button"))
    expect(upload_section).not_to include("disabled") # dropzone/upload controls stay enabled
  end

  it "preserves processing before pending before error ordering within Confirmed Files" do
    error_doc = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :error)
    pending_doc = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
    processing_doc = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :processing)

    confirmed_panel = panel_body(documents_tab, "documents-panel-confirmed")

    expect(confirmed_panel.index(dom_id(processing_doc)))
      .to be < confirmed_panel.index(dom_id(pending_doc))
    expect(confirmed_panel.index(dom_id(pending_doc)))
      .to be < confirmed_panel.index(dom_id(error_doc))
  end

  it "puts every document in exactly one panel" do
    unconfirmed = create(:kyc_document, applicant: applicant, classification_status: :unclassified)
    confirmed = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :pending)
    processed = create(:kyc_document, applicant: applicant, classification_status: :confirmed, status: :complete)

    body = documents_tab
    panels = %w[documents-panel-unconfirmed documents-panel-confirmed documents-panel-processed]
      .map { |id| panel_body(body, id) }

    [ unconfirmed, confirmed, processed ].each do |document|
      matches = panels.count { |panel| panel.include?(dom_id(document)) }
      expect(matches).to eq(1), "expected #{dom_id(document)} in exactly one panel, found in #{matches}"
    end
  end
end
