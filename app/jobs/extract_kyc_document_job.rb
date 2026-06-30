# frozen_string_literal: true

class ExtractKycDocumentJob < ApplicationJob
  include KycDocumentBroadcaster

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
    send_onboarding_feedback(document)
  rescue KyneticOcrClient::Error, ClaudeOcrAdapter::Error, Kyc::Inference::Error,
         Kyc::GroupStructureExtractorService::ExtractionError, Kyc::DocumentExtractorService::Error => e
    document&.update!(status: :error, result: { "error" => e.message })
    if document
      broadcast_document(document)
      broadcast_toast(document)
      send_onboarding_feedback(document)
    end
  end

  private

  def send_onboarding_feedback(document)
    return unless document.applicant.onboarding_session&.document_collection?

    Onboarding::DocumentFeedbackService.call(document)
  end

  def extract_group_structure(document)
    Kyc::GroupStructureExtractorService.call(document)
    document.update!(status: :complete)
  end

  def extract_standard(document)
    response = Kyc::DocumentExtractorService.call(document)
    typed_data = document.extraction_schema.new(response)

    match = PrincipalMatcherService.call(
      applicant: document.applicant,
      document_type: document.document_type,
      result: matcher_hash(typed_data)
    )

    address_match = if match.principal && Kyc::DocumentCategory.proof_of_address?(document.document_type)
      populate_address(match.principal, typed_data)
      AddressMatcherService.call(
        principal: match.principal,
        extracted_address: address_string(typed_data)
      )
    end

    document.update!(
      status: :complete,
      extracted_data: response,
      kyc_principal: match.principal,
      match_method: match.match_method,
      match_confidence: match.match_confidence,
      address_match_method: address_match&.match_method,
      address_match_confidence: address_match&.match_confidence
    )
  end

  def matcher_hash(typed_data)
    return {} unless typed_data.respond_to?(:to_matcher_hash)

    typed_data.to_matcher_hash.transform_values do |value|
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end
  end

  def populate_address(principal, typed_data)
    return if principal.address_line1.present?

    attrs = {
      address_line1: typed_data.structured_address[:line1],
      city: typed_data.structured_address[:city],
      postcode: typed_data.structured_address[:postcode],
      country: typed_data.structured_address[:country]
    }.compact_blank

    return if attrs.empty?

    principal.update!(attrs)
  end

  def address_string(typed_data)
    typed_data.structured_address.values.compact_blank.join(", ")
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
end
