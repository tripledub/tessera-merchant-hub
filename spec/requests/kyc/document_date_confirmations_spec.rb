# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::DocumentDateConfirmations", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin) }

  let_it_be(:applicant) { create(:applicant) }

  let!(:document) do
    create(:kyc_document, applicant: applicant, validity_dates: {
      "expiry" => { "raw" => "2030-01-01", "normalized" => "2030-01-01", "confidence" => 0.95,
                    "provenance" => "ai_extraction" },
      "issued" => { "raw" => nil, "normalized" => nil, "confidence" => nil, "provenance" => "ai_extraction" }
    })
  end

  describe "POST /kyc/document_date_confirmations" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "confirms an unchanged extracted date without a reason" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" }

        expect(response).to have_http_status(:ok).or have_http_status(:redirect)
        confirmation = Kyc::DocumentDateConfirmation.last
        expect(confirmation.date_role).to eq("expiry")
        expect(confirmation.confirmed_value).to eq(Date.new(2030, 1, 1))
        expect(confirmation.extracted_value).to eq(Date.new(2030, 1, 1))
        expect(confirmation.confirmed_by).to eq(psp_admin)
      end

      it "enters a missing date without a reason" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "issued", confirmed_value: "2031-04-01" }

        expect(Kyc::DocumentDateConfirmation.last.confirmed_value).to eq(Date.new(2031, 4, 1))
        expect(Kyc::DocumentDateConfirmation.last.extracted_value).to be_nil
      end

      it "rejects a date_role that was not extracted for this document" do
        expect do
          post kyc_document_date_confirmations_path,
               params: { kyc_document_id: document.id, date_role: "bogus_role", confirmed_value: "2030-01-01" }
        end.not_to change(Kyc::DocumentDateConfirmation, :count)

        expect(response).to have_http_status(:unprocessable_content).or have_http_status(:redirect)
      end

      it "rejects a changed date without a reason" do
        expect do
          post kyc_document_date_confirmations_path,
               params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2032-01-01" }
        end.not_to change(Kyc::DocumentDateConfirmation, :count)

        expect(response).to have_http_status(:unprocessable_content).or have_http_status(:redirect)
      end

      it "accepts a changed date with a reason and creates a new audit row" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2032-01-01",
                       reason: "Passport renewed" }

        confirmation = Kyc::DocumentDateConfirmation.last
        expect(confirmation.confirmed_value).to eq(Date.new(2032, 1, 1))
        expect(confirmation.extracted_value).to eq(Date.new(2030, 1, 1))
        expect(confirmation.reason).to eq("Passport renewed")
      end

      it "creates a new audit row rather than overwriting a prior confirmation" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" }

        expect do
          post kyc_document_date_confirmations_path,
               params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2033-01-01",
                         reason: "Second correction" }
        end.to change(Kyc::DocumentDateConfirmation, :count).by(1)

        expect(Kyc::DocumentDateConfirmation.where(kyc_document: document, date_role: "expiry").count).to eq(2)
      end

      it "confirms successfully and returns a turbo stream response for turbo_stream format" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(Kyc::DocumentDateConfirmation.count).to eq(1)
      end

      it "returns a turbo stream response with errors on validation failure for turbo_stream format" do
        expect do
          post kyc_document_date_confirmations_path,
               params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2032-01-01" },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end.not_to change(Kyc::DocumentDateConfirmation, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "does not repeat the confirmation history inside the per-role date confirmation card (MH-209)" do
        # Confirmation history is shown once, in the document-level audit trail
        # (Kyc::DocumentValidityPresenter#confirmation_history). The per-role
        # date confirmation card used to render the same entries again via
        # Kyc::DocumentDateConfirmationPresenter#history_for, which was
        # confusing duplication when a document has a single date role.
        document.update!(document_type: :passport)

        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        card = fragment.css("#date_confirmation_#{ActionView::RecordIdentifier.dom_id(document)}_expiry")

        expect(card.first.css("li")).to be_empty
        expect(fragment.css("[data-testid='confirmation-history'] li").size).to eq(1)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" }

        expect(response).to have_http_status(:forbidden)
        expect(Kyc::DocumentDateConfirmation.count).to eq(0)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" }

        expect(response).to have_http_status(:forbidden)
        expect(Kyc::DocumentDateConfirmation.count).to eq(0)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post kyc_document_date_confirmations_path,
             params: { kyc_document_id: document.id, date_role: "expiry", confirmed_value: "2030-01-01" }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
