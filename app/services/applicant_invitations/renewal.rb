# frozen_string_literal: true

module ApplicantInvitations
  # Sends a fresh invitation link when an applicant asks for one from a dead
  # link. It acts only for an expired invitation that was never used or revoked,
  # not more than once per cooldown, and always to the address the PSP invited
  # (never one supplied by the requester). Returns the new invitation, or nil
  # when nothing was sent; callers must not let that difference show.
  module Renewal
    COOLDOWN = 10.minutes

    module_function

    def call(token:)
      invitation = ApplicantInvitation.find_by_token(token)
      return unless invitation&.expired? && invitation.claimed_at.nil? && invitation.revoked_at.nil?

      invitation.with_lock do
        next if recently_renewed?(invitation)

        renewed, new_token = ApplicantInvitation.issue!(
          applicant: invitation.applicant, email: invitation.email, invited_by: invitation.invited_by
        )
        ApplicantInvitationMailer.renewal(renewed, encrypted_link_for(new_token)).deliver_later
        renewed
      end
    end

    # The mail job's arguments are stored in the queue database, so the link
    # goes in encrypted, never as plaintext (MH-412).
    def encrypted_link_for(token)
      ShortLivedSecret.encrypt(
        link_for(token), purpose: ApplicantInvitation::RENEWAL_MAIL_PURPOSE, expires_in: ApplicantInvitation::RENEWAL_MAIL_LIFETIME
      )
    end
    private_class_method :encrypted_link_for

    def recently_renewed?(invitation)
      ApplicantInvitation.where(applicant_id: invitation.applicant_id, email: invitation.email)
                         .where.not(id: invitation.id)
                         .exists?([ "created_at > ?", COOLDOWN.ago ])
    end
    private_class_method :recently_renewed?

    # Built from the configured public host, never from the request: the
    # request's Host header is attacker-controlled on this public endpoint.
    def link_for(token)
      Rails.application.routes.url_helpers.portal_invitation_url(
        token: token, **ActionMailer::Base.default_url_options
      )
    end
    private_class_method :link_for
  end
end
