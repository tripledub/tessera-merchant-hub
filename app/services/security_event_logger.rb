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

    # For events raised inside services, where there is no request. Details must
    # never include secrets (codes, tokens) or raw personal data; use
    # `fingerprint` for an email address.
    def log_event(event:, **details)
      Rails.logger.warn({ event: event }.merge(details).to_json)
    end

    # A stable keyed hash for correlating events about the same value (an email
    # address) without logging the value itself. Its own key, so it cannot be
    # matched against the request-source fingerprints.
    def fingerprint(value)
      key = Rails.application.key_generator.generate_key("security-event-subject", 32)
      OpenSSL::HMAC.hexdigest("SHA256", key, value.to_s)
    end

    private

    def source_fingerprint(source)
      key = Rails.application.key_generator.generate_key("security-event-source", 32)
      OpenSSL::HMAC.hexdigest("SHA256", key, source.to_s)
    end
  end
end
