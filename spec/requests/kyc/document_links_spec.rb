# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::DocumentLinks", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Doe", status: :unconfirmed) }

  describe "PATCH /kyc/document_links/:id" do
    let!(:document) do
      create(:kyc_document, applicant: applicant, kyc_principal: principal,
             match_method: "fuzzy", match_confidence: 0.95)
    end

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "confirms the principal and updates match to exact" do
        patch kyc_document_link_path(document)

        expect(response).to have_http_status(:ok)
        expect(document.reload.match_method).to eq("exact")
        expect(document.reload.match_confidence).to eq(1.0)
        expect(principal.reload.status).to eq("confirmed")
      end

      it "broadcasts a turbo stream update" do
        patch kyc_document_link_path(document)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      end
    end

    # Honeybadger 133725885: KycDocumentBroadcaster renders a kyc_document
    # fragment via Turbo::StreamsChannel.broadcast_replace_to, which uses
    # ActionController::Renderer and so has no Warden::Proxy on its request
    # env. Calling policy(document) there raised Devise::MissingWarden
    # whenever the document had validity_dates — but every other spec here
    # stubs Turbo::StreamsChannel.broadcast_replace_to entirely, which skips
    # the real render and would never catch this. Stub only the ActionCable
    # publish step so the render (and its bug) actually executes.
    context "when the broadcast partial renders for real" do
      let!(:document) do
        create(:kyc_document, applicant: applicant, kyc_principal: principal,
               match_method: "fuzzy", match_confidence: 0.95,
               validity_dates: { "expiry" => { "raw" => "x", "normalized" => "2030-01-01",
                 "confidence" => 0.95, "provenance" => "ai_extraction" } })
      end

      before { sign_in psp_admin }

      it "does not raise Devise::MissingWarden and actually broadcasts (not a silent no-op)" do
        broadcasts = []
        allow(ActionCable.server).to receive(:broadcast) { |_streamable, payload| broadcasts << payload }

        expect { patch kyc_document_link_path(document) }.not_to raise_error

        expect(response).to have_http_status(:ok)
        expect(broadcasts).not_to be_empty
      end

      # The confirm/correct-dates section is gated on a Pundit policy check
      # that needs a real signed-in viewer (see ApplicationController#viewer_can?).
      # A broadcast has no such viewer, so it must never attempt to render
      # that section — not even to correctly hide it — because the broadcast
      # target scopes only the document metadata (see
      # KycDocumentBroadcaster#broadcast_document): rendering the full
      # document fragment here would blank out the confirmation section for
      # every connected viewer, including an admin who already had it open
      # from a real, correctly-authorized render.
      it "broadcasts only the user-independent metadata fragment, not the date-confirmation section" do
        broadcasts = []
        allow(ActionCable.server).to receive(:broadcast) { |_streamable, payload| broadcasts << payload }

        patch kyc_document_link_path(document)

        expect(broadcasts.size).to eq(1)
        expect(broadcasts.first).to include("kyc_document_#{document.id}_metadata")
        expect(broadcasts.first).not_to include("date_confirmation_")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch kyc_document_link_path(document)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        patch kyc_document_link_path(document)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "DELETE /kyc/document_links/:id" do
    let!(:document) do
      create(:kyc_document, applicant: applicant, kyc_principal: principal,
             match_method: "exact", match_confidence: 1.0)
    end

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "unlinks the document from the principal" do
        delete kyc_document_link_path(document),
               headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        document.reload
        expect(document.kyc_principal).to be_nil
        expect(document.match_method).to be_nil
        expect(document.match_confidence).to be_nil
      end

      it "returns a turbo stream remove action" do
        delete kyc_document_link_path(document),
               headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
      end

      it "redirects back for HTML requests" do
        delete kyc_document_link_path(document),
               headers: { "HTTP_REFERER" => applicant_path(applicant) }

        expect(response).to redirect_to(applicant_path(applicant))
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete kyc_document_link_path(document)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        delete kyc_document_link_path(document)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
