# frozen_string_literal: true

require "openssl"

class SecurityEventLogger
  class << self
    def log(event:, request:)
      Rails.logger.warn(
        {
          event: event,
          controller: request.path_parameters[:controller],
          action: request.path_parameters[:action],
          request_id: request.request_id,
          source_fingerprint: source_fingerprint(request.remote_ip)
        }.to_json
      )
    end

    private

    def source_fingerprint(source)
      key = Rails.application.key_generator.generate_key("security-event-source", 32)
      OpenSSL::HMAC.hexdigest("SHA256", key, source.to_s)
    end
  end
end
