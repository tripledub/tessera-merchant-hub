# frozen_string_literal: true

class ProcessKycDocumentJob < ApplicationJob
  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)
    document.processing!
    broadcast_document(document)

    response = ocr_client(document)

    match = PrincipalMatcherService.call(applicant: document.applicant, result: response)
    document.update!(
      status:           :complete,
      result:           response,
      kyc_principal:    match.principal,
      match_method:     match.match_method,
      match_confidence: match.match_confidence
    )
    broadcast_document(document)
  rescue KyneticOcrClient::Error, ClaudeOcrAdapter::Error => e
    document&.update!(status: :error, result: { "error" => e.message })
    broadcast_document(document) if document
  end

  private

  def ocr_client(document)
    if !Rails.env.production? && ENV["CLAUDE_OCR"].present?
      ClaudeOcrAdapter.process(document: document)
    else
      KyneticOcrClient.process(
        customer_id: document.applicant_id,
        document_key: document.file.key
      )
    end
  end

  def broadcast_document(document)
    Turbo::StreamsChannel.broadcast_replace_to(
      "applicant_#{document.applicant_id}_documents",
      target: "kyc_document_#{document.id}",
      partial: "kyc_documents/kyc_document",
      locals: { document: document }
    )
  end
end
