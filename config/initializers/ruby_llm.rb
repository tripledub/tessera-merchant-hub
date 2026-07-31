# frozen_string_literal: true

RubyLLM.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key

  # Silences deprecation warning for the legacy acts_as_chat/acts_as_message API,
  # which this app doesn't use.
  config.use_new_acts_as = true
end
