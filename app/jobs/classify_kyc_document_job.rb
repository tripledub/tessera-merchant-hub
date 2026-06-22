# frozen_string_literal: true

class ClassifyKycDocumentJob < ApplicationJob
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
  rescue DocumentClassifiers::AiFallback::Error, HandlerRegisterable::NoHandlerAccepted => e
    document&.update!(status: :error, result: { "error" => e.message })
    broadcast_document(document) if document
  end

  private

  def classification_status_for(classifier)
    case classifier
    when DocumentClassifiers::AiFallback then :ai_suggested
    else :auto_classified
    end
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
