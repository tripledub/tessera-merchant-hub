# frozen_string_literal: true

class ProcessKycDocumentJob < ApplicationJob
  include KycDocumentBroadcaster
  include OcrClientResolvable

  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)
    document.processing!
    broadcast_document(document)

    response = ocr_client(document)

    match = PrincipalMatcherService.call(applicant: document.applicant, document_type: response["document_type"], result: response)
    address_match = if match.principal && response["document_type"] == "utility_bill"
      AddressMatcherService.call(
        principal:         match.principal,
        extracted_address: response["address"]
      )
    end

    document.update!(
      status:                   :complete,
      result:                   response,
      kyc_principal:            match.principal,
      match_method:             match.match_method,
      match_confidence:         match.match_confidence,
      address_match_method:     address_match&.match_method,
      address_match_confidence: address_match&.match_confidence
    )
    broadcast_document(document)
  rescue KyneticOcrClient::Error, ClaudeOcrAdapter::Error => e
    document&.update!(status: :error, result: { "error" => e.message })
    broadcast_document(document) if document
  end
end
