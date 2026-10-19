# frozen_string_literal: true

module ApplicantSignInCodes
  # Issues a one-time sign-in code for an applicant's address and emails it
  # (MH-404). The limits are counted from the code rows themselves, per applicant
  # and address, so they hold across processes (the rate-limit cache does not).
  # Only a keyed digest of the code is stored; the plaintext code reaches the
  # mailer encrypted (the job queue is a database that keeps its arguments).
  module Issue
    MIN_GAP = 30.seconds
    HOURLY_CAP = 10
    DAILY_CAP = 20

    # status: :sent, :too_soon or :rate_limited. retry_after: seconds to wait
    # (nil when sent).
    Result = Data.define(:status, :retry_after)

    module_function

    def call(applicant:, email:, invitation: nil)
      email = ApplicantSignInCode.normalize_value_for(:email, email.to_s)
      record = nil
      code = nil

      refusal = ApplicantSignInCode.transaction do
        lock_for(applicant, email)
        reason, wait = refusal_for(applicant, email)
        next [ reason, wait ] if reason

        code = ApplicantSignInCode.generate_code
        record = create_code(applicant, email, invitation, code)
        nil
      end

      return refuse(*refusal, email) if refusal

      deliver(record, code)
      log(:issued, record, email)
      Result.new(status: :sent, retry_after: nil)
    end

    # One issuance at a time per applicant and address, or two requests arriving
    # together could both pass the limits.
    def lock_for(applicant, email)
      ApplicantSignInCode.connection.execute(
        ApplicantSignInCode.sanitize_sql_array(
          [ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", "#{applicant.id}:#{email}" ]
        )
      )
    end
    private_class_method :lock_for

    # [reason, seconds to wait], or nil when a new code may be issued.
    def refusal_for(applicant, email)
      scope = ApplicantSignInCode.where(applicant_id: applicant.id, email: email)
      now = Time.current

      latest = scope.maximum(:created_at)
      return [ :too_soon, (latest + MIN_GAP - now).ceil ] if latest && latest + MIN_GAP > now

      [ [ :hourly, 1.hour, HOURLY_CAP ], [ :daily, 1.day, DAILY_CAP ] ].each do |reason, window, cap|
        recent = scope.where("created_at > ?", now - window)
        next if recent.count < cap

        return [ reason, (recent.minimum(:created_at) + window - now).ceil ]
      end
      nil
    end
    private_class_method :refusal_for

    def create_code(applicant, email, invitation, code)
      ApplicantSignInCode.where(applicant_id: applicant.id, email: email, consumed_at: nil, invalidated_at: nil)
                         .update_all(invalidated_at: Time.current)

      record = ApplicantSignInCode.new(
        applicant: applicant, email: email, applicant_invitation: invitation,
        applicant_user: ApplicantUser.find_by(applicant_id: applicant.id, email: email),
        expires_at: ApplicantSignInCode::LIFETIME.from_now, id: SecureRandom.uuid
      )
      record.code_digest = ApplicantSignInCode.digest_for(id: record.id, code: code)
      record.save!
      record
    end
    private_class_method :create_code

    def deliver(record, code)
      encrypted = ShortLivedSecret.encrypt(
        code, purpose: ApplicantSignInCode::MAIL_PURPOSE, expires_in: ApplicantSignInCode::MAIL_TOKEN_LIFETIME
      )
      ApplicantSignInCodeMailer.code(record, encrypted).deliver_later
    end
    private_class_method :deliver

    def refuse(reason, wait, email)
      SecurityEventLogger.log_event(
        event: "portal.sign_in_code.rate_limited", reason: reason, email_fingerprint: SecurityEventLogger.fingerprint(email)
      )
      Result.new(status: reason == :too_soon ? :too_soon : :rate_limited, retry_after: wait)
    end
    private_class_method :refuse

    def log(outcome, record, email)
      SecurityEventLogger.log_event(
        event: "portal.sign_in_code.#{outcome}", code_id: record.id, email_fingerprint: SecurityEventLogger.fingerprint(email)
      )
    end
    private_class_method :log
  end
end
