# frozen_string_literal: true

module Kyc
  # MH-199: the daily job that closes the gap left intentionally open by
  # MH-198 (see Applicant#validity_reference_date) — expires-mode documents
  # (passports) that genuinely expire mid-review would otherwise never be
  # re-evaluated against real calendar time. This job calls
  # Kyc::DocumentValidity::Assessor.assess_or_reuse(reference_date:
  # Date.current) once per day for every active, expires-mode-policy-governed
  # document, which both keeps assessment history honest over time AND
  # drives a Kyc::DocumentReplacementRequirement through warned -> escalated
  # -> closed.
  #
  # Freshness-mode documents (utility bills) are deliberately never selected
  # here — they are only assessed against a stable application/review
  # reference date (MH-198's territory), per the epic's documented
  # "Out of Scope: continuous recollection of freshness documents outside an
  # active application or compliance review."
  #
  # Idempotency (retries must not duplicate warnings/assessments/
  # requirements) comes from three layers, deliberately with NO separate
  # "job run" ledger table (YAGNI — none of the gaps below need one):
  #   1. Assessor.assess_or_reuse already dedups same-day/same-input
  #      assessments (MH-198).
  #   2. Requirement state transitions are guarded by current state (a
  #      requirement is only created if one doesn't exist yet; escalate!/
  #      close! are no-ops if already in that state or beyond it).
  #   3. A DB-level unique index on kyc_document_replacement_requirements.
  #      kyc_document_id catches a race between overlapping runs trying to
  #      create the same requirement concurrently.
  class DocumentExpiryMonitoringJob < ApplicationJob
    queue_as :default

    # The lowest configured warning_thresholds value is the escalation
    # point ("30 days" in the initial [90, 30] config) — anything above the
    # minimum is treated as the *initial* warning. This generalizes beyond
    # the specific 90/30 numbers named in the AC to whatever thresholds a
    # policy is actually configured with.
    def perform(reference_date: Date.current)
      monitored_documents(reference_date).find_each do |document|
        process_document(document, reference_date)
      end

      reconcile_open_requirements(reference_date)
    end

    private

    def monitored_documents(reference_date)
      types = eligible_expiry_document_types(reference_date)
      return KycDocument.none if types.empty?

      # "Active" = successfully extracted (status: complete) and not
      # already replaced by a newer upload of the same type.
      KycDocument.where(document_type: types, status: :complete).not_superseded
    end

    def eligible_expiry_document_types(reference_date)
      KycDocument.document_types.keys.select do |document_type|
        policy = Kyc::DocumentValidity::PolicyResolver.resolve(
          document_type: document_type, reference_date: reference_date
        )
        policy.present? && policy.mode == "expires"
      end
    end

    def process_document(document, reference_date)
      policy = Kyc::DocumentValidity::PolicyResolver.resolve(
        document_type: document.document_type, reference_date: reference_date
      )
      return if policy.nil? || policy.mode != "expires"

      assessment = Kyc::DocumentValidity::Assessor.assess_or_reuse(document: document, reference_date: reference_date)
      return if assessment.nil?

      if assessment.expiring_soon_outcome?
        handle_expiring_soon(document, assessment, policy)
      elsif assessment.expired_outcome?
        handle_expired(document)
      end
      # valid_outcome? / confirmation_required_outcome? need no requirement
      # action here — supersession reconciliation (closing an existing open
      # requirement once a valid replacement shows up) is handled
      # separately, in #reconcile_open_requirements, for every open
      # requirement regardless of what today's assessment of the OLD
      # document says.
    end

    def handle_expiring_soon(document, assessment, policy)
      threshold_days = assessment.reason_details && assessment.reason_details["threshold_days"]
      escalation_point = Array(policy.warning_thresholds).min
      crossed_escalation_point = threshold_days.present? && threshold_days == escalation_point

      requirement = Kyc::DocumentReplacementRequirement.current_for(document)

      if requirement.nil?
        create_requirement!(document, status: crossed_escalation_point ? :escalated : :warned)
      elsif crossed_escalation_point
        requirement.escalate!
      end
    end

    # Gap case: a document is already expired but was never seen crossing a
    # warning threshold first (policy enabled after the fact, or a missed
    # run). Conservatively open the requirement already escalated, since
    # it's already past expiry — never leave an expired, unmonitored
    # document with no open requirement at all.
    def handle_expired(document)
      requirement = Kyc::DocumentReplacementRequirement.current_for(document)
      return if requirement

      create_requirement!(document, status: :escalated, escalated: true)
    end

    def create_requirement!(document, status:, escalated: false)
      now = Time.current
      attrs = { kyc_document: document, status: status, opened_at: now }
      attrs[:escalated_at] = now if status == :escalated || escalated

      Kyc::DocumentReplacementRequirement.create!(attrs)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Another run (or another thread of this same run) created the
      # requirement first — the DB-backed unique index is the source of
      # truth here, so losing this race is not an error.
      nil
    end

    def reconcile_open_requirements(reference_date)
      Kyc::DocumentReplacementRequirement.where(status: %i[warned escalated]).find_each do |requirement|
        close_if_replaced!(requirement, reference_date)
      end
    end

    def close_if_replaced!(requirement, reference_date)
      old_document = requirement.kyc_document
      candidate = replacement_candidate(old_document, reference_date)
      return if candidate.nil?

      old_document.update!(superseded_by_kyc_document: candidate)
      requirement.close!(superseded_by: candidate)
    end

    # A "confirmed valid replacement" is the oldest newer upload of the same
    # document_type for the same subject (applicant/principal/corporate
    # entity — matched exactly the way the old document is scoped) that has
    # been successfully extracted and assesses as valid or expiring_soon.
    # Deliberately conservative: checked here, during the daily job's own
    # run, rather than hooked into the extraction job pipeline — there is no
    # existing "link this upload as the replacement for that one" flow
    # anywhere in the codebase (MH-200 will build the UI), so reconciling
    # once a day from a single, auditable place is safer than reaching into
    # ExtractKycDocumentJob's completion path.
    def replacement_candidate(old_document, reference_date)
      KycDocument.where(
        document_type: old_document.document_type,
        applicant_id: old_document.applicant_id,
        kyc_principal_id: old_document.kyc_principal_id,
        corporate_entity_id: old_document.corporate_entity_id,
        status: :complete,
        superseded_by_kyc_document_id: nil
      ).where("created_at > ?", old_document.created_at)
        .where.not(id: old_document.id)
        .order(created_at: :asc)
        .find do |candidate|
        candidate_assessment = Kyc::DocumentValidity::Assessor.assess_or_reuse(
          document: candidate, reference_date: reference_date
        )
        candidate_assessment.present? && (candidate_assessment.valid_outcome? || candidate_assessment.expiring_soon_outcome?)
      end
    end
  end
end
