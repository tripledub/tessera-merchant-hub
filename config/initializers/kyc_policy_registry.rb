# frozen_string_literal: true

Rails.application.reloader.to_prepare do
  I18n::Railtie.initialize_i18n(Rails.application)
  Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
end
