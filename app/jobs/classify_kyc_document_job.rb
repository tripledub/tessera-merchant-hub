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
      content_type: document.file.content_type,
      document: document
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
    notify_honeybadger(e, kyc_document_id, document)
    broadcast_after_classification_failure(document)
  end

  private

  # Deliberately does not pass the exception (or its #message) to
  # Honeybadger: JSON::ParserError and RubyLLM::Error messages can echo back
  # fragments of the AI model's response or the underlying API error body,
  # which is derived from the KYC document's own content — not safe to hand
  # to a third-party service. Only our own controlled, pre-known-safe values
  # go in the report.
  #
  # cause: nil is required, not just omitted: Honeybadger::Notice falls back
  # to Ruby's $! (the exception currently being handled — i.e. `e` itself)
  # whenever no :cause is given and no :exception object was passed, so
  # without this the "sanitized" report would still get the original
  # exception silently reattached as its cause/backtrace chain.
  #
  # Runs before broadcast_after_classification_failure so a Turbo/ActionCable
  # failure there can't suppress the alert.
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

  # We're still inside the `rescue ... => e` handler here, so Ruby's
  # implicit exception chaining would otherwise attach the original
  # (potentially sensitive) classification error as this new exception's
  # #cause — which could then reach a generic job-failure reporter (e.g. an
  # ActiveJob/Sidekiq Honeybadger integration serializing the raised error's
  # full cause chain) even though notify_honeybadger above was careful not
  # to. Re-raise a fresh exception instance with cause: nil explicitly:
  # re-raising the same already-raised object doesn't work here, since Ruby
  # only assigns #cause the first time an exception is raised.
  def broadcast_after_classification_failure(document)
    return unless document

    broadcast_document(document)
  rescue => broadcast_error
    raise broadcast_error.class.new(broadcast_error.message), cause: nil
  end

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
