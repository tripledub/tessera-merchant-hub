# frozen_string_literal: true

Rails.application.config.to_prepare do
  Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
end
