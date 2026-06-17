# frozen_string_literal: true

class ProcessKycDocumentJob < ApplicationJob
  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)
    document.processing!
    broadcast_document(document)

    response = KyneticOcrClient.process(
      customer_id: document.applicant_id,
      document_key: document.file.key
    )

    principal = match_principal(document.applicant, response["full_name"])
    document.update!(status: :complete, result: response, kyc_principal: principal)
    broadcast_document(document)
  rescue KyneticOcrClient::Error => e
    document&.update!(status: :error, result: { "error" => e.message })
    broadcast_document(document) if document
  end

  private

  def match_principal(applicant, full_name)
    return nil if full_name.blank?

    applicant.kyc_principals.find { |p| p.name.downcase == full_name.downcase }
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
