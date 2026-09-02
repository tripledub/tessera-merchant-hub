# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KycDocuments", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  describe "POST /applicants/:applicant_id/kyc_documents" do
    let(:file) { fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.pdf"), "application/pdf") }

    before { create_fixture_file }

    def create_fixture_file
      dir = Rails.root.join("spec/fixtures/files")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("sample.pdf"), "%PDF-1.4 fake content")
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "enqueues a ClassifyKycDocumentJob and redirects to applicant" do
        expect {
          post applicant_kyc_documents_path(applicant), params: {
            kyc_document: { files: [ file ] }
          }
        }.to have_enqueued_job(ClassifyKycDocumentJob)
        expect(response).to redirect_to(applicant_path(applicant))
      end

      it "redirects with alert when no files provided" do
        post applicant_kyc_documents_path(applicant), params: { kyc_document: { files: [] } }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:alert]).to be_present
      end

      # MH-210: uploading must never trigger a full page reload — the tab
      # the user is on (and the client-side dropzone form state) is only
      # preserved if the response stays a turbo_stream.
      it "appends the new document into the list instead of redirecting, when requesting turbo_stream" do
        post applicant_kyc_documents_path(applicant),
          params: { kyc_document: { files: [ file ] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")

        new_document = applicant.kyc_documents.last
        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("##{ActionView::RecordIdentifier.dom_id(new_document)}")).to be_present
        expect(fragment.css("turbo-stream[action='append'][target='toast-container']")).to be_present
      end

      it "removes the empty-state placeholder when this is the applicant's first document" do
        post applicant_kyc_documents_path(applicant),
          params: { kyc_document: { files: [ file ] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).to include('turbo-stream action="remove" target="kyc-documents-empty"')
      end

      it "does not try to remove the empty-state placeholder when the applicant already has documents" do
        create(:kyc_document, applicant: applicant)

        post applicant_kyc_documents_path(applicant),
          params: { kyc_document: { files: [ file ] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).not_to include("kyc-documents-empty")
      end

      it "renders only the toast, with no document append, when no files are provided via turbo_stream" do
        post applicant_kyc_documents_path(applicant),
          params: { kyc_document: { files: [] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("turbo-stream").size).to eq(1)
        expect(fragment.css("turbo-stream[action='append'][target='toast-container']")).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicant_kyc_documents_path(applicant), params: {
          kyc_document: { files: [ file ] }
        }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post applicant_kyc_documents_path(applicant), params: { kyc_document: { files: [] } }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "DELETE /kyc_documents/:id" do
    let_it_be(:document) { create(:kyc_document, applicant: applicant) }

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      end

      it "destroys the document and returns 200" do
        delete kyc_document_path(document)
        expect(response).to have_http_status(:ok)
        expect(KycDocument.find_by(id: document.id)).to be_nil
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete kyc_document_path(document)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /kyc_documents/:id" do
    let_it_be(:document) do
      create(:kyc_document, applicant: applicant, document_type: :passport, classification_status: :auto_classified)
    end

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "confirms classification without triggering extraction" do
        patch kyc_document_path(document),
          params: { kyc_document: { classification_status: "confirmed" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(document.reload.classification_status).to eq("confirmed")
        expect(ExtractKycDocumentJob).not_to have_been_enqueued
      end

      it "allows overriding the document type" do
        patch kyc_document_path(document),
          params: { kyc_document: { document_type: "utility_bill", classification_status: "confirmed" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(document.reload.document_type).to eq("utility_bill")
        expect(document.classification_status).to eq("confirmed")
      end

      it "ignores invalid document types" do
        patch kyc_document_path(document),
          params: { kyc_document: { document_type: "invalid_type" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(document.reload.document_type).to eq("passport")
      end

      it "ignores routing-only document types" do
        patch kyc_document_path(document),
          params: { kyc_document: { document_type: "processing_statement" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(document.reload.document_type).to eq("passport")
        expect(document.processing_statement).to be_nil
      end

      it "renders the validity status inside a single dom_id-wrapped element (MH-208)" do
        # A turbo_stream.replace can only remove content living inside its target
        # element. Confirming the classification repeatedly used to leave the
        # validity badge (and date confirmation blocks) as orphaned siblings of
        # the replaced element, so each confirm click left an extra "Not tracked"
        # badge behind instead of replacing the previous one.
        patch kyc_document_path(document),
          params: { kyc_document: { classification_status: "confirmed" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        wrapper = fragment.css("##{ActionView::RecordIdentifier.dom_id(document)}")

        expect(wrapper.size).to eq(1)
        expect(wrapper.first.css("[data-testid='document-validity-status']")).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch kyc_document_path(document), params: { kyc_document: { classification_status: "confirmed" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /kyc_documents/:id/retry" do
    let_it_be(:document) { create(:kyc_document, applicant: applicant, status: :error) }

    context "when signed in as psp_admin" do
      before do
        sign_in psp_admin
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "resets the document and enqueues ClassifyKycDocumentJob" do
        expect {
          post retry_kyc_document_path(document)
        }.to have_enqueued_job(ClassifyKycDocumentJob).with(document.id)
        expect(response).to have_http_status(:ok)
        expect(document.reload.status).to eq("pending")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post retry_kyc_document_path(document)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /kyc_documents/:id/comment_status" do
    let_it_be(:merchant_admin) { create(:user, :merchant_admin) }
    let!(:document) { create(:kyc_document, applicant: applicant) }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "sets the comment_status to requires_follow_up" do
        patch comment_status_kyc_document_path(document), params: { comment_status: "requires_follow_up" }

        expect(document.reload.comment_status).to eq("requires_follow_up")
      end

      it "sets the comment_status to resolved" do
        patch comment_status_kyc_document_path(document), params: { comment_status: "resolved" }

        expect(document.reload.comment_status).to eq("resolved")
      end

      it "ignores an invalid comment_status value" do
        patch comment_status_kyc_document_path(document), params: { comment_status: "bogus" }

        expect(document.reload.comment_status).to be_nil
      end

      it "returns a turbo stream response replacing the document row" do
        patch comment_status_kyc_document_path(document),
              params: { comment_status: "resolved" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("##{ActionView::RecordIdentifier.dom_id(document)}")).to be_present
      end

      it "returns a turbo stream response also updating the comments modal content with the updated highlight" do
        patch comment_status_kyc_document_path(document),
              params: { comment_status: "resolved" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("##{ActionView::RecordIdentifier.dom_id(document)}")).to be_present

        modal_stream = fragment.css('turbo-stream[target="document-comments-modal"]')
        expect(modal_stream).to be_present

        buttons = modal_stream.css("form button")
        resolved_button = buttons.find { |b| b.text.include?("Mark resolved") }
        expect(resolved_button["class"]).to include("ring-success-400")
      end

      it "updates the comments modal in place (turbo_stream update, not replace) so the frame element's identity is preserved" do
        patch comment_status_kyc_document_path(document),
              params: { comment_status: "resolved" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)

        modal_stream = fragment.css('turbo-stream[target="document-comments-modal"]')
        expect(modal_stream).to be_present
        expect(modal_stream.attr("action").value).to eq("update")

        # The stream must NOT contain a nested <turbo-frame id="document-comments-modal">
        # element — that would mean the frame itself is being replaced (outerHTML swap),
        # which destroys any JS expando/dataset state stored on the persistent frame node.
        expect(modal_stream.css("turbo-frame#document-comments-modal")).to be_empty
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "sets the comment_status" do
        patch comment_status_kyc_document_path(document), params: { comment_status: "resolved" }

        expect(document.reload.comment_status).to eq("resolved")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch comment_status_kyc_document_path(document), params: { comment_status: "resolved" }

        expect(response).to have_http_status(:forbidden)
        expect(document.reload.comment_status).to be_nil
      end

      it "returns 403, not 406, for a turbo stream request" do
        patch comment_status_kyc_document_path(document),
              params: { comment_status: "resolved" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:forbidden)
        expect(document.reload.comment_status).to be_nil
      end
    end
  end

  describe "document row rendering with comment_status set" do
    let!(:document) { create(:kyc_document, applicant: applicant, comment_status: "requires_follow_up") }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows the comment_status badge on the applicant documents tab" do
        get tab_applicant_path(applicant, tab: "documents")

        expect(response.body).to include("Requires follow up")
      end

      it "shows the comments trigger icon on the document row" do
        get tab_applicant_path(applicant, tab: "documents")

        expect(response.body).to include(kyc_document_comments_path(document))
      end

      it "gives the comments trigger a stable, deterministic id derived from the document id" do
        get tab_applicant_path(applicant, tab: "documents")

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("##{ActionView::RecordIdentifier.dom_id(document)} ##{"comments-trigger-#{document.id}"}")).to be_present
      end
    end
  end

  describe "accessible labels on icon-only document row actions" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "labels the file preview button" do
        document = create(:kyc_document, applicant: applicant)

        get tab_applicant_path(applicant, tab: "documents")

        row = row_fragment_for(document)
        preview_button = row.css("button[data-controller='document-preview']").first
        expect(preview_button["aria-label"]).to eq(I18n.t("kyc.documents.preview"))
      end

      it "labels the classification confirm button" do
        document = create(:kyc_document, applicant: applicant, status: :pending)

        get tab_applicant_path(applicant, tab: "documents")

        row = row_fragment_for(document)
        confirm_button = row.css("button[data-action='click->classification#confirm']").first
        expect(confirm_button["aria-label"]).to eq(I18n.t("kyc.documents.confirm"))
      end

      it "labels the confirm/reject principal match buttons" do
        principal = create(:kyc_principal, applicant: applicant, status: :unconfirmed)
        document = create(:kyc_document, applicant: applicant, kyc_principal: principal)

        get tab_applicant_path(applicant, tab: "documents")

        row = row_fragment_for(document)
        buttons = row.css("form button")
        confirm_match = buttons.find { |b| b["aria-label"] == I18n.t("kyc.documents.confirm_match") }
        reject_match = buttons.find { |b| b["aria-label"] == I18n.t("kyc.documents.reject_match") }
        expect(confirm_match).to be_present
        expect(reject_match).to be_present
      end

      it "labels the retry button" do
        document = create(:kyc_document, applicant: applicant, status: :error)

        get tab_applicant_path(applicant, tab: "documents")

        row = row_fragment_for(document)
        retry_button = row.css("form button").find { |b| b["aria-label"] == I18n.t("kyc.documents.retry") }
        expect(retry_button).to be_present
      end

      it "labels the comments trigger" do
        document = create(:kyc_document, applicant: applicant)

        get tab_applicant_path(applicant, tab: "documents")

        row = row_fragment_for(document)
        expect(row.css("#comments-trigger-#{document.id}").first["aria-label"]).to eq(I18n.t("kyc.documents.comments.open"))
      end

      it "labels the delete button and requires confirmation before submitting" do
        document = create(:kyc_document, applicant: applicant)

        get tab_applicant_path(applicant, tab: "documents")

        row = row_fragment_for(document)
        delete_button = row.css("form[action='#{kyc_document_path(document)}'] button").first
        expect(delete_button["aria-label"]).to eq(I18n.t("kyc.documents.delete"))
        expect(delete_button["data-turbo-confirm"]).to eq(
          I18n.t("kyc.documents.delete_confirm", filename: document.file.filename)
        )
      end
    end

    def row_fragment_for(document)
      fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
      fragment.css("##{ActionView::RecordIdentifier.dom_id(document)}").first
    end
  end

  describe "sticky upload shortcut in the documents header" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows a labelled jump-to-upload shortcut in the sticky header, next to Run extraction, that scrolls without touching the hash-based tab router" do
        create(:kyc_document, applicant: applicant)

        get tab_applicant_path(applicant, tab: "documents")

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        header = fragment.css(".sticky").first
        upload_button = header.css("button[data-scroll-to-target-value='kyc-upload']").first
        expect(upload_button).to be_present
        expect(upload_button["type"]).to eq("button")
        expect(upload_button["aria-label"]).to eq(I18n.t("applicants.show.documents.upload_document"))
        expect(header.css("form[action='#{applicant_kyc_extraction_run_path(applicant)}']")).to be_present
      end

      it "shows the upload shortcut even when the document list is empty" do
        get tab_applicant_path(applicant, tab: "documents")

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("button[data-scroll-to-target-value='kyc-upload']")).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "does not show the upload shortcut (no create permission)" do
        get tab_applicant_path(applicant, tab: "documents")

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        expect(fragment.css("button[data-scroll-to-target-value='kyc-upload']")).to be_empty
      end
    end
  end
end
