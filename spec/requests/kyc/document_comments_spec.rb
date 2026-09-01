# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::DocumentComments", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin) }
  let_it_be(:applicant)      { create(:applicant) }
  let_it_be(:document)       { create(:kyc_document, applicant: applicant) }

  describe "GET /kyc_documents/:kyc_document_id/comments" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "renders the modal with an empty state when there are no comments" do
        get kyc_document_comments_path(document)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("document-comments-modal")
      end

      it "renders existing comments" do
        create(:comment, commentable: document, author: psp_admin, body: "Please re-upload, blurry scan")

        get kyc_document_comments_path(document)

        expect(response.body).to include("Please re-upload, blurry scan")
      end

      it "shows both status buttons and highlights the active one" do
        resolved_document = create(:kyc_document, applicant: applicant, comment_status: "resolved")

        get kyc_document_comments_path(resolved_document)

        expect(response.body).to include("Mark requires follow up")
        expect(response.body).to include("Mark resolved")

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        buttons = fragment.css("form button")
        resolved_button = buttons.find { |b| b.text.include?("Mark resolved") }
        follow_up_button = buttons.find { |b| b.text.include?("Mark requires follow up") }

        expect(resolved_button["class"]).to include("ring-success-400")
        expect(follow_up_button["class"]).not_to include("ring-warning-400")
      end

      it "highlights the requires-follow-up button when that status is active" do
        follow_up_document = create(:kyc_document, applicant: applicant, comment_status: "requires_follow_up")

        get kyc_document_comments_path(follow_up_document)

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        buttons = fragment.css("form button")
        resolved_button = buttons.find { |b| b.text.include?("Mark resolved") }
        follow_up_button = buttons.find { |b| b.text.include?("Mark requires follow up") }

        expect(follow_up_button["class"]).to include("ring-warning-400")
        expect(resolved_button["class"]).not_to include("ring-success-400")
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get kyc_document_comments_path(document)

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get kyc_document_comments_path(document)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /kyc_documents/:kyc_document_id/comments" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates a comment authored by the current user" do
        expect {
          post kyc_document_comments_path(document), params: { body: "Needs a follow up call" }
        }.to change(Comment, :count).by(1)

        comment = Comment.last
        expect(comment.commentable).to eq(document)
        expect(comment.author).to eq(psp_admin)
        expect(comment.body).to eq("Needs a follow up call")
      end

      it "renders the modal with the new comment" do
        post kyc_document_comments_path(document), params: { body: "Needs a follow up call" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Needs a follow up call")
      end

      it "does not create a comment when body is blank" do
        expect {
          post kyc_document_comments_path(document), params: { body: "" }
        }.not_to change(Comment, :count)
      end

      it "renders a distinguishable failure state when body is blank" do
        post kyc_document_comments_path(document), params: { body: "" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("can&#39;t be blank")
      end

      it "marks the invalid textarea for autofocus instead of a status button" do
        post kyc_document_comments_path(document), params: { body: "" }

        fragment = Nokogiri::HTML::DocumentFragment.parse(response.body)
        textarea = fragment.css("textarea[name='body']").first

        expect(textarea["data-modal-autofocus"]).to eq("true")
        expect(textarea["aria-invalid"]).to eq("true")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "creates a comment" do
        expect {
          post kyc_document_comments_path(document), params: { body: "Confirmed with applicant" }
        }.to change(Comment, :count).by(1)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403 and does not create a comment" do
        expect {
          post kyc_document_comments_path(document), params: { body: "Should not persist" }
        }.not_to change(Comment, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403, not 406, for a turbo stream request" do
        expect {
          post kyc_document_comments_path(document),
               params: { body: "Should not persist" },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        }.not_to change(Comment, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        post kyc_document_comments_path(document), params: { body: "Should not persist" }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
