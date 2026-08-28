class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Safe alternative to `policy(record).query` for partials that may be
  # rendered outside a real request — e.g. a KycDocumentBroadcaster /
  # Turbo::StreamsChannel.broadcast_*_to render, which uses
  # ActionController::Renderer and has no Warden::Proxy on its request env.
  # Devise's `current_user` raises Devise::MissingWarden in that context, so
  # we treat "no warden" as unauthorized rather than let it raise. A truthy
  # `warden` doesn't by itself guarantee a signed-in user (e.g. an
  # unauthenticated real request) and most ApplicationPolicy predicates call
  # `user.some_role?` with no nil guard, so check current_user too rather
  # than let that raise NoMethodError on a nil user.
  def viewer_can?(record, query)
    return false unless request.env["warden"] && current_user

    policy(record).public_send(query)
  end
  helper_method :viewer_can?

  private

  def user_not_authorized
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.json { render json: { error: "Forbidden" }, status: :forbidden }
      format.text { render plain: "Forbidden", status: :forbidden }
    end
  end
end
