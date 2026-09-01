# frozen_string_literal: true

class Kyc::DocumentCommentsController < ApplicationController
  expose(:kyc_document) { KycDocument.find(params[:document_id]) }

  def index
    authorize kyc_document, policy_class: Kyc::DocumentCommentPolicy
    render partial: "kyc/document_comments/modal", locals: { kyc_document: kyc_document, comment_errors: nil }, layout: false
  end

  def create
    authorize kyc_document, policy_class: Kyc::DocumentCommentPolicy
    # Built via Comment.new (not kyc_document.comments.new) so a failed save
    # doesn't leave an unsaved, created_at-less record sitting in the
    # comments association's in-memory target — the modal iterates
    # kyc_document.comments and would try to render that phantom entry.
    comment = Comment.new(commentable: kyc_document, author: current_user, body: params[:body])
    status = comment.save ? :ok : :unprocessable_content

    render partial: "kyc/document_comments/modal",
           locals: { kyc_document: kyc_document, comment_errors: comment.errors.presence },
           layout: false,
           status: status
  end
end
