# frozen_string_literal: true

module Portal
  module AbuseProtection
    extend ActiveSupport::Concern

    REGISTRATION_PAYLOAD_LIMIT = 64.kilobytes
    APPLICATION_PAYLOAD_LIMIT = 256.kilobytes

    class_methods do
      def portal_rate_limit_store
        @portal_rate_limit_store ||= Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
      end
    end

    private

    def reject_oversized_portal_payload(limit)
      return if request.content_length.to_i <= limit

      SecurityEventLogger.log(event: "portal.payload_rejected", request: request)
      head :content_too_large
    end

    def portal_rate_limited
      SecurityEventLogger.log(event: "portal.rate_limited", request: request)
      head :too_many_requests
    end

    def log_invalid_portal_access
      SecurityEventLogger.log(event: "portal.invalid_access", request: request)
    end
  end
end
