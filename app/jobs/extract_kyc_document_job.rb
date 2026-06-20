# frozen_string_literal: true

class ExtractKycDocumentJob < ApplicationJob
  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)

    unless document.classification_confirmed?
      Rails.logger.warn("ExtractKycDocumentJob: skipping #{document.id} — classification not confirmed")
      return
    end

    document.processing!
    broadcast_document(document)

    response = ocr_client(document)

    match = PrincipalMatcherService.call(applicant: document.applicant, result: response)
    address_match = if match.principal && document.utility_bill?
      AddressMatcherService.call(
        principal: match.principal,
        extracted_address: response["address"]
      )
    end

    document.update!(
      status: :complete,
      result: response,
      kyc_principal: match.principal,
      match_method: match.match_method,
      match_confidence: match.match_confidence,
      address_match_method: address_match&.match_method,
      address_match_confidence: address_match&.match_confidence
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
