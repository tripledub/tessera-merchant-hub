# frozen_string_literal: true

class ApplicantInvitationMailer < ApplicationMailer
  def invite(invitation, url)
    @invitation = invitation
    @url = url
    mail(to: invitation.email, subject: t(".subject", applicant: invitation.applicant.name))
  end
end
