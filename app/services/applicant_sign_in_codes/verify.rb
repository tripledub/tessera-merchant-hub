# frozen_string_literal: true

module ApplicantSignInCodes
  # Checks a one-time sign-in code (MH-404). Only the latest code for the
  # applicant and address counts: an older one entered after a new code is
  # requested is just a wrong attempt. The code row is locked while it is
  # checked, so the attempt count cannot be raced past the limit and a right
  # code is accepted once.
  #
  # The outcome describes only this address's own code, so the screens can show
  # each state without revealing anything about other accounts.
  module Verify
    # status: :verified, :wrong, :expired, :used, :locked or :none.
    # attempts_left: only for :wrong. applicant_user: an existing user for the
    # address (confirmed on success), or nil; nobody is created here.
    Result = Data.define(:status, :attempts_left, :applicant_user)

    module_function

    def call(applicant:, email:, code:)
      email = ApplicantSignInCode.normalize_value_for(:email, email.to_s)
      latest = ApplicantSignInCode.where(applicant_id: applicant.id, email: email).order(created_at: :desc).first
      return Result.new(status: :none, attempts_left: nil, applicant_user: nil) unless latest

      result = latest.with_lock { evaluate(latest, code.to_s) }
      log(result.status, latest, email)
      result
    end

    def evaluate(record, code)
      return result(:used) if record.consumed?
      return result(:locked) if record.locked?
      return result(:expired) if record.expired?

      record.attempts += 1
      if record.matches?(code)
        record.update!(consumed_at: Time.current)
        result(:verified, user: confirm_user(record))
      elsif record.attempts >= ApplicantSignInCode::MAX_ATTEMPTS
        record.update!(invalidated_at: Time.current)
        result(:locked)
      else
        record.save!
        result(:wrong, attempts_left: ApplicantSignInCode::MAX_ATTEMPTS - record.attempts)
      end
    end
    private_class_method :evaluate

    def confirm_user(record)
      user = ApplicantUser.find_by(applicant_id: record.applicant_id, email: record.email)
      user&.confirm unless user.nil? || user.confirmed?
      user
    end
    private_class_method :confirm_user

    def result(status, attempts_left: nil, user: nil)
      Result.new(status: status, attempts_left: attempts_left, applicant_user: user)
    end
    private_class_method :result

    def log(status, record, email)
      SecurityEventLogger.log_event(
        event: "portal.sign_in_code.#{status}", code_id: record.id, attempts: record.attempts,
        email_fingerprint: SecurityEventLogger.fingerprint(email)
      )
    end
    private_class_method :log
  end
end
