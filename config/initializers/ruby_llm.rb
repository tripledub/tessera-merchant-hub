# frozen_string_literal: true

RubyLLM.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key
end
