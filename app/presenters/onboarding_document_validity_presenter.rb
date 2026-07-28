# frozen_string_literal: true

# MH-200: Applicant-facing document validity/replacement notices, rendered
# on the existing onboarding chat page (app/views/onboarding/conversations/
# show.html.erb) — the ONLY applicant-facing surface this app has, during
# AND after onboarding completes (there is no separate "your account"
# portal; see investigation notes on MH-200).
#
# Deliberately a SEPARATE, minimal-vocabulary presenter from
# Kyc::DocumentValidityPresenter (the staff one) rather than the same class
# with fields selectively hidden: its public interface — #notices, each a
# Notice(document_type_label:, message:) — never even reads confidence,
# reason_code, confirmed_by/staff identity, or policy_version, so there is
# no field on this object an Applicant-facing view could accidentally
# render to leak them.
class OnboardingDocumentValidityPresenter < BasePresenter
  presents :onboarding_session

  Notice = Data.define(:document_type_label, :message)

  def notices
    documents.filter_map { |document| notice_for(document) }
  end

  private

  def applicant
    onboarding_session.applicant
  end

  def documents
    applicant.kyc_documents.not_superseded.where.not(document_type: nil)
  end

  def notice_for(document)
    replacement = Kyc::DocumentReplacementRequirement.current_for(document)
    return build_notice(document, :replacement_required) if replacement && !replacement.closed?

    assessment = Kyc::DocumentValidity::Assessor.assess_or_reuse(
      document: document, reference_date: applicant.validity_reference_date
    )
    return nil if assessment.nil?

    if assessment.expired_outcome? || assessment.stale_outcome?
      build_notice(document, :invalid)
    elsif assessment.confirmation_required_outcome?
      build_notice(document, :under_review)
    end
  end

  def build_notice(document, key)
    label = document_type_label(document)
    Notice.new(document_type_label: label,
               message: I18n.t("onboarding.conversations.document_status.#{key}", document_type: label))
  end

  def document_type_label(document)
    I18n.t("kyc.documents.document_types.#{document.document_type}")
  end
end
