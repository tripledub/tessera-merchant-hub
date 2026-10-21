# frozen_string_literal: true

module Onboarding
  # MH-422: after the chat's upload is classified (or fails), the applicant is told
  # the outcome in fixed words, saved to the conversation so a reload shows the same
  # history. One message per document and outcome.
  module DocumentOutcomeMessage
    MARKDOWN_SPECIALS = /([\\`*_{}\[\]()#+\-.!<>|~])/

    module_function

    # The saved bot message, or nil when there is no chat to tell (no session, or not
    # in the documents stage) or this outcome was already said for this document.
    def record!(document)
      session = document.applicant.onboarding_session
      return unless session&.document_collection?

      outcome = outcome_for(document)
      return if already_said?(session, document, outcome)

      session.onboarding_messages.create!(
        role: :bot, stage: session.current_stage, content: content_for(document, outcome),
        structured_data: { "kyc_document_id" => document.id.to_s, "outcome" => outcome.to_s }
      )
    end

    def outcome_for(document)
      return :error if document.error?

      document.document_type.present? ? :recognised : :unrecognised
    end
    private_class_method :outcome_for

    def already_said?(session, document, outcome)
      session.onboarding_messages.where("structured_data ->> 'kyc_document_id' = ?", document.id.to_s)
             .where("structured_data ->> 'outcome' = ?", outcome.to_s).exists?
    end
    private_class_method :already_said?

    def content_for(document, outcome)
      case outcome
      when :recognised
        label = I18n.t("kyc.documents.document_types.#{document.document_type}")
        I18n.t("onboarding.document_outcome.recognised", document_type: label)
      when :unrecognised
        I18n.t("onboarding.document_outcome.unrecognised", filename: filename_for(document))
      else
        I18n.t("onboarding.document_outcome.error", filename: filename_for(document))
      end
    end
    private_class_method :content_for

    # The applicant's own file name, with anything the markdown renderer would act on escaped.
    def filename_for(document)
      document.file.filename.to_s.gsub(MARKDOWN_SPECIALS) { "\\#{Regexp.last_match(1)}" }
    end
    private_class_method :filename_for
  end
end
