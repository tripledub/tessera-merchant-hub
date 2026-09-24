# frozen_string_literal: true

require "rails_helper"

# MH-200: staff-facing document validity/replacement/confirmation-history
# display on the applicant documents tab, and confirmation that the
# existing MH-196 confirm/correct turbo_stream response now also refreshes
# this new content (widened from the narrower per-role target it used to
# replace).
RSpec.describe "Kyc document validity display", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  let(:applicant) { create(:applicant) }

  def get_documents_tab
    get tab_applicant_path(applicant, tab: "documents")
  end

  before do
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport", effective_from: Date.new(2020, 1, 1),
      mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
    )
  end

  context "when signed in as psp_admin" do
    before { sign_in psp_admin }

    it "shows the Valid outcome distinctly" do
      create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "x",
               "normalized" => (applicant.validity_reference_date + 2.years).iso8601, "confidence" => 0.95,
               "provenance" => "ai_extraction" } })

      get_documents_tab

      expect(response.body).to include("Valid")
      expect(response.body).to include("Within the validity window.")
    end

    it "shows the Expired outcome distinctly, without raw extraction data" do
      create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "x",
               "normalized" => (applicant.validity_reference_date - 1).iso8601, "confidence" => 0.95,
               "provenance" => "ai_extraction" } })

      get_documents_tab

      expect(response.body).to include("Expired")
      expect(response.body).to include("Past the document&#39;s printed expiry date.")
      expect(response.body).not_to include("0.95")
    end

    it "shows the Awaiting review (confirmation_required) outcome distinctly from a rejection" do
      create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => nil, "normalized" => nil, "confidence" => nil,
               "provenance" => "ai_extraction" } })

      get_documents_tab

      expect(response.body).to include("Awaiting review")
    end

    it "shows the Not tracked (no-assessment) case for a document type outside the validity rollout" do
      create(:kyc_document, applicant: applicant, document_type: :driving_licence, status: :complete,
             classification_status: :confirmed)

      get_documents_tab

      expect(response.body).to include("Not tracked")
    end

    it "shows open replacement progress" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "x",
               "normalized" => (applicant.validity_reference_date + 10).iso8601, "confidence" => 0.95,
               "provenance" => "ai_extraction" } })
      create(:kyc_document_replacement_requirement, kyc_document: document, status: :escalated,
             escalated_at: Time.current)

      get_documents_tab

      expect(response.body).to include("Replacement urgently required")
    end

    it "shows confirmation history" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })
      Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", extracted_value: Date.new(2030, 1, 1),
        confirmed_value: Date.new(2031, 6, 1), confirmed_by: psp_admin, reason: "Renewed"
      )

      get_documents_tab

      expect(response.body).to include("confirmation-history")
      expect(response.body).to include(psp_admin.email)
      expect(response.body).to include("Renewed")
      # MH-200 AC requires both the original (extracted) value and the
      # confirmed value be visible, not just the confirmed value, so a
      # reviewer can see what a correction changed FROM.
      expect(response.body).to include("2030-01-01")
      expect(response.body).to include("2031-06-01")
    end

    it "shows a missing date entered from scratch distinctly from a correction of an extracted value" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => nil, "normalized" => nil, "confidence" => nil,
               "provenance" => "ai_extraction" } })
      Kyc::DocumentDateConfirmation.create!(
        kyc_document: document, date_role: "expiry", extracted_value: nil,
        confirmed_value: Date.new(2031, 6, 1), confirmed_by: psp_admin
      )

      get_documents_tab

      expect(response.body).to include("2031-06-01")
      expect(response.body).to include("no date was extracted")
    end

    it "still offers the existing MH-196 confirm/correct interaction alongside the new status display" do
      # MH-322: the confirm/correct form itself moved into a modal opened from
      # the row's overflow menu, so the documents tab now carries the trigger,
      # not the form.
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })

      get_documents_tab

      expect(response.body).to include("document-validity-status")
      expect(response.body).to include(date_confirmation_modal_kyc_document_path(document))
      # The menu trigger reads "Confirm dates" (a superset string of the
      # modal's own submit button "Confirm date"), so check for the actual
      # form control rather than a loose substring match.
      fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
      expect(fragment.css("input[type=submit][value='#{t_confirm_date}']")).to be_empty
    end

    it "renders the confirm/correct form in the date confirmation modal" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })

      get date_confirmation_modal_kyc_document_path(document)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(t_confirm_date)
      expect(response.body).to include(document.file.filename.to_s)
    end

    it "refreshes the validity status via the existing confirm/correct turbo_stream response" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2029-01-01", "normalized" => "2029-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })

      post kyc_document_date_confirmations_path,
           params: { kyc_document_id: document.id, date_role: "expiry",
                     confirmed_value: (applicant.validity_reference_date + 2.years).iso8601,
                     reason: "Renewed" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Valid")
      expect(response.body).to include("document-validity-status")
    end

    it "does not show a validity assessment before classification is confirmed (MH-323)" do
      create(:kyc_document, applicant: applicant, document_type: :passport, status: :pending,
             classification_status: :ai_suggested)

      get_documents_tab

      expect(response.body).not_to include("Awaiting review")
      expect(response.body).not_to include("A required date could not be confirmed")
    end
  end

  context "when signed in as psp_support" do
    before { sign_in psp_support }

    it "cannot confirm dates" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2029-01-01", "normalized" => "2029-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })

      post kyc_document_date_confirmations_path,
           params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" }

      expect(response).to have_http_status(:forbidden)
    end

    it "does not render the MH-196 confirm/correct interaction on the documents tab" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })

      get_documents_tab

      expect(response.body).not_to include(t_confirm_date)
      expect(response.body).not_to include(date_confirmation_modal_kyc_document_path(document))
    end

    it "cannot open the date confirmation modal" do
      document = create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
             classification_status: :confirmed,
             validity_dates: { "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01",
               "confidence" => 0.95, "provenance" => "ai_extraction" } })

      get date_confirmation_modal_kyc_document_path(document)

      expect(response).to have_http_status(:forbidden)
    end
  end

  def t_confirm_date
    I18n.t("kyc.documents.date_confirmations.submit")
  end
end
