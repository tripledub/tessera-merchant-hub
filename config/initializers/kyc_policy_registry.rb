# frozen_string_literal: true

Rails.application.config.after_initialize do
  Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
end
