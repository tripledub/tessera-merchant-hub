# frozen_string_literal: true

module Portal
  # Shared by the pages an applicant sees from an invitation link. They show an
  # email address or answer for a token, so they are never cached or indexed, and
  # every dead link (unknown, expired, used, revoked) gets the same page.
  module InvitationPage
    extend ActiveSupport::Concern

    private

    def prevent_caching_and_indexing
      response.headers["Cache-Control"] = "no-store"
      response.headers["X-Robots-Tag"] = "noindex"
    end

    def render_dead_link(token)
      log_invalid_portal_access
      prevent_caching_and_indexing
      render "portal/invitations/dead_link", status: :not_found, locals: { token: token.to_s.presence || "-" }
    end
  end
end
