# frozen_string_literal: true

class ClassifyKycDocumentJob < ApplicationJob
  include KycDocumentBroadcaster

  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)
    document.processing!
    broadcast_document(document)

    condition = DocumentClassifiers::Condition.new(
      filename: document.file.filename.to_s,
      content_type: document.file.content_type
    )

    classifier = DocumentClassifiers.obtain(condition)
    result = classifier.classify

    document.update!(
      status: :pending,
      document_type: result[:document_type],
      classification_status: classification_status_for(classifier),
      classification_confidence: result[:confidence],
      classification_method: result[:classification_method].to_s
    )
    broadcast_document(document)
    auto_confirm_for_onboarding(document)
  rescue DocumentClassifiers::AiFallback::Error, HandlerRegisterable::NoHandlerAccepted => e
    document&.update!(status: :error, result: { "error" => e.message })
    broadcast_document(document) if document
  end

  private

  def auto_confirm_for_onboarding(document)
    return unless document.classification_auto_classified?

    session = document.applicant.onboarding_session
    return unless session&.document_collection?
    return unless Onboarding::DocumentCollectionService.checklist_expects?(session, document.document_type)

    document.update!(classification_status: :confirmed)
    ExtractKycDocumentJob.perform_later(document.id)
  end

  def classification_status_for(classifier)
    case classifier
    when DocumentClassifiers::AiFallback then :ai_suggested
    else :auto_classified
    end
  end
end
