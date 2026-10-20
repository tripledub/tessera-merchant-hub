# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    [
      Portal::InvitationsController,
      Portal::InvitationRenewalsController,
      Portal::RegistrationsController,
      Portal::SessionsController,
      Portal::SignInCodesController,
      Portal::ApplicationsController
    ].each { |controller| controller.portal_rate_limit_store.clear }
  end
end
