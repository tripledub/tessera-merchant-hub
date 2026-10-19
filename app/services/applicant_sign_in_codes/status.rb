# frozen_string_literal: true

module ApplicantSignInCodes
  # Which screen the enter-code page shows for an applicant's address (MH-405),
  # worked out from the latest code row alone, so a refresh is always consistent
  # with what the code service will accept. Reads only; it never changes a row.
  module Status
    # state: :active, :expired, :used, :locked or :none. resend_in: seconds
    # until another code may be requested (0 when it may be now).
    Result = Data.define(:state, :resend_in)

    module_function

    def call(applicant:, email:)
      email = ApplicantSignInCode.normalize_value_for(:email, email.to_s)
      latest = ApplicantSignInCode.where(applicant_id: applicant.id, email: email).order(created_at: :desc).first
      return Result.new(state: :none, resend_in: 0) unless latest

      Result.new(state: state_of(latest), resend_in: resend_in(latest))
    end

    def state_of(code)
      return :used if code.consumed?
      return :locked if code.locked?
      return :expired if code.expired?

      :active
    end
    private_class_method :state_of

    def resend_in(code)
      [ (code.created_at + Issue::MIN_GAP - Time.current).ceil, 0 ].max
    end
    private_class_method :resend_in
  end
end
