# frozen_string_literal: true

module ApplicantSignInCodes
  # The stand-in for a code that does not exist (MH-406). An address with no
  # account is answered as if a code had been sent, so nobody can tell whether an
  # account exists. The decoy counts attempts down, locks, expires, and refuses
  # to resend exactly as the real code service does, from numbers the visitor
  # carries in their own session. It stores nothing, sends nothing, and has no
  # code to match, so it can never sign anyone in.
  module Decoy
    # status: :wrong, :locked, :expired, :sent, :too_soon or :rate_limited.
    Outcome = Data.define(:status, :attempts, :attempts_left, :sent_at, :retry_after)

    # Compared with, so a guess costs the same keyed work as a real check.
    NEVER_MATCHES = ("0" * 64).freeze

    module_function

    # sent_at: epoch seconds of every send, oldest first.
    def status(attempts:, sent_at:, now: Time.current)
      last = sent_at.last
      state = if attempts >= ApplicantSignInCode::MAX_ATTEMPTS then :locked
      elsif last.nil? || now.to_i >= last + ApplicantSignInCode::LIFETIME then :expired
      else :active
      end
      Status::Result.new(state: state, resend_in: last ? [ last + Issue::MIN_GAP.to_i - now.to_i, 0 ].max : 0)
    end

    def verify(attempts:, sent_at:, code:, now: Time.current)
      state = status(attempts: attempts, sent_at: sent_at, now: now).state
      return outcome(state, attempts, sent_at) unless state == :active

      ActiveSupport::SecurityUtils.secure_compare(ApplicantSignInCode.digest_for(id: "decoy", code: code.to_s), NEVER_MATCHES)
      attempts += 1
      return outcome(:locked, attempts, sent_at) if attempts >= ApplicantSignInCode::MAX_ATTEMPTS

      outcome(:wrong, attempts, sent_at, attempts_left: ApplicantSignInCode::MAX_ATTEMPTS - attempts)
    end

    def resend(sent_at:, attempts: 0, now: Time.current)
      now_i = now.to_i
      kept = sent_at.select { |time| time > now_i - 1.day.to_i }
      last = kept.last
      if last && last + Issue::MIN_GAP.to_i > now_i
        return outcome(:too_soon, attempts, kept, retry_after: last + Issue::MIN_GAP.to_i - now_i)
      end

      wait = refusal_wait(kept, now_i)
      return outcome(:rate_limited, attempts, kept, retry_after: wait) if wait

      outcome(:sent, 0, kept + [ now_i ])
    end

    def refusal_wait(kept, now_i)
      recent = kept.select { |time| time > now_i - 1.hour.to_i }
      return recent.min + 1.hour.to_i - now_i if recent.size >= Issue::HOURLY_CAP

      kept.min + 1.day.to_i - now_i if kept.size >= Issue::DAILY_CAP
    end
    private_class_method :refusal_wait

    def outcome(status, attempts, sent_at, attempts_left: nil, retry_after: nil)
      Outcome.new(status: status, attempts: attempts, attempts_left: attempts_left, sent_at: sent_at, retry_after: retry_after)
    end
    private_class_method :outcome
  end
end
