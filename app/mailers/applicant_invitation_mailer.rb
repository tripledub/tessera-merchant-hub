# frozen_string_literal: true

class ApplicantInvitationMailer < ApplicationMailer
  def invite(invitation, url)
    @invitation = invitation
    @url = url
    mail(to: invitation.email, subject: t(".subject", applicant: invitation.applicant.name))
  end

  # The renewal is sent in the background, and a background job's arguments are
  # stored in the queue database, so its link arrives encrypted (MH-412) and is
  # only decrypted here, when the email is built. If it cannot be (it expired
  # while the job waited, or was altered), nothing is sent.
  def renewal(invitation, encrypted_url)
    @url = ShortLivedSecret.decrypt(encrypted_url, purpose: ApplicantInvitation::RENEWAL_MAIL_PURPOSE)
    return if @url.blank?

    @invitation = invitation
    mail(to: invitation.email, subject: t("applicant_invitation_mailer.invite.subject", applicant: invitation.applicant.name),
         template_name: "invite")
  end
end
