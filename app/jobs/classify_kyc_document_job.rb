# frozen_string_literal: true

class ClassifyKycDocumentJob < ApplicationJob
  include KycDocumentBroadcaster

  # Deliberately not a re-raise of the original broadcast error: some
  # exception classes (e.g. ActionView::Template::Error) override #cause to
  # return an ivar set from $! in their own #initialize, which raise(...,
  # cause: nil) cannot suppress.
  class BroadcastAfterClassificationFailureError < StandardError; end

  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)
    document.processing!
    broadcast_document(document)

    condition = DocumentClassifiers::Condition.new(
      filename: document.file.filename.to_s,
      content_type: document.file.content_type,
      document: document
    )

    classifier = DocumentClassifiers.obtain(condition)
    result = classifier.classify
    unsupported_content_type = result[:classification_method] == :unsupported_content_type

    document.update!(
      status: unsupported_content_type ? :complete : :pending,
      document_type: result[:document_type],
      classification_status: classification_status_for(result),
      classification_confidence: result[:confidence],
      classification_method: result[:classification_method].to_s
    )
    broadcast_document(document)
    auto_confirm_for_onboarding(document) unless unsupported_content_type
  rescue DocumentClassifiers::AiFallback::Error, HandlerRegisterable::NoHandlerAccepted => e
    document&.update!(status: :error, result: { "error" => e.message })
    notify_honeybadger(e, kyc_document_id, document)
    broadcast_after_classification_failure(document)
  end

  private

  # error/message deliberately excluded: both can echo back document-derived
  # content (e.g. JSON::ParserError quoting the AI's raw response). cause:
  # nil is required, not just omitted — Honeybadger::Notice otherwise falls
  # back to $! (== exception, inside this rescue) and reattaches it anyway.
  def notify_honeybadger(exception, kyc_document_id, document)
    Honeybadger.notify(
      "KYC document classification failed",
      cause: nil,
      context: {
        kyc_document_id: kyc_document_id,
        content_type: document&.file&.content_type,
        error_class: exception.class.name
      }
    )
  end

  # Wraps in a plain error we control rather than re-raising broadcast_error
  # (or `broadcast_error.class.new(...)`): still inside the outer rescue, so
  # the original classification exception would otherwise reach whatever
  # reports this job's raised errors via #cause.
  def broadcast_after_classification_failure(document)
    return unless document

    broadcast_document(document)
  rescue => broadcast_error
    sanitized = BroadcastAfterClassificationFailureError.new(
      "KYC document error-state broadcast failed (#{broadcast_error.class.name})"
    )
    sanitized.set_backtrace(broadcast_error.backtrace)
    raise sanitized, cause: nil
  end

  def auto_confirm_for_onboarding(document)
    return unless document.classification_auto_classified?

    session = document.applicant.onboarding_session
    return unless session&.document_collection?
    return unless Onboarding::DocumentCollectionService.checklist_expects?(session, document.document_type)

    document.update!(classification_status: :confirmed)
    ExtractKycDocumentJob.perform_later(document.id)
  end

  def classification_status_for(result)
    case result[:classification_method]
    when :ai then :ai_suggested
    else :auto_classified
    end
  end
end
