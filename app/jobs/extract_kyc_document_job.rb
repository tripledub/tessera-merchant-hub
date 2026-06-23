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

    if document.group_structure_chart?
      extract_group_structure(document)
    else
      extract_standard(document)
    end

    broadcast_document(document)
    broadcast_toast(document)
  rescue KyneticOcrClient::Error, ClaudeOcrAdapter::Error, Kyc::Inference::Error, Kyc::GroupStructureExtractorService::ExtractionError => e
    document&.update!(status: :error, result: { "error" => e.message })
    if document
      broadcast_document(document)
      broadcast_toast(document)
    end
  end

  private

  def extract_group_structure(document)
    Kyc::GroupStructureExtractorService.call(document)
    document.update!(status: :complete)
  end

  def extract_standard(document)
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
  end

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

  def broadcast_toast(document)
    type = document.error? ? :error : :success
    message = if document.error?
      "Extraction failed: #{document.file.filename}"
    else
      "Extraction complete: #{document.file.filename}"
    end

    Turbo::StreamsChannel.broadcast_append_to(
      "applicant_#{document.applicant_id}_documents",
      target: "toast-container",
      partial: "shared/toast",
      locals: { message: message, type: type }
    )
  end

  def broadcast_document(document)
    Turbo::StreamsChannel.broadcast_replace_to(
      "applicant_#{document.applicant_id}_documents",
      target: "kyc_document_#{document.id}",
      partial: "kyc/documents/kyc_document",
      locals: { document: document }
    )
  end
end
