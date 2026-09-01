# frozen_string_literal: true

class Kyc::DocumentCommentsController < ApplicationController
  expose(:kyc_document) { KycDocument.find(params[:document_id]) }

  def index
    authorize kyc_document, policy_class: Kyc::DocumentCommentPolicy
    render partial: "kyc/document_comments/modal", locals: { kyc_document: kyc_document }, layout: false
  end

  def create
    authorize kyc_document, policy_class: Kyc::DocumentCommentPolicy
    kyc_document.comments.create(author: current_user, body: params[:body])
    render partial: "kyc/document_comments/modal", locals: { kyc_document: kyc_document }, layout: false
  end
end
