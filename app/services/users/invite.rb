# frozen_string_literal: true

module Users
  class Invite
    PERMITTED_ROLES = %w[psp_admin psp_support merchant_admin merchant_viewer].freeze
    private_constant :PERMITTED_ROLES

    def self.call(params) = new(params).call

    def initialize(params)
      @email       = params[:email].to_s.strip
      @role        = params[:role].to_s
      @merchant_id = params[:merchant_id]
    end

    def call
      return invalid_role_user unless PERMITTED_ROLES.include?(@role)

      user = User.new(
        email:       @email,
        role:        @role,
        merchant_id: @merchant_id,
        password:    SecureRandom.hex(24)
      )

      # send_reset_password_instructions generates a reset token and enqueues
      # the invitation email. In production, ActionMailer delivers asynchronously
      # so mailer failures don't affect the user record. In development,
      # letter_opener_web delivers synchronously — mailer errors would propagate,
      # but this is acceptable in a dev environment.
      user.send_reset_password_instructions if user.save

      user
    end

    private

    def invalid_role_user
      user = User.new
      user.errors.add(:role, "is not permitted")
      user
    end
  end
end
