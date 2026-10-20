# frozen_string_literal: true

# Emails a one-time sign-in code (MH-404). The code arrives encrypted: it is a
# background job argument, and Solid Queue stores those in the database, so it
# must not be plaintext there. If it cannot be decrypted (it expired while the
# job waited), nothing is sent.
class ApplicantSignInCodeMailer < ApplicationMailer
  def code(sign_in_code, encrypted_code)
    @code = ShortLivedSecret.decrypt(encrypted_code, purpose: ApplicantSignInCode::MAIL_PURPOSE)
    return if @code.blank?

    @expires_in_minutes = (ApplicantSignInCode::LIFETIME / 1.minute).to_i
    mail(to: sign_in_code.email, subject: t(".subject"))
  end
end
