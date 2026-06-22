# frozen_string_literal: true

module Kyc
  module Inference
    class Error < StandardError; end

    class << self
      def adapter
        @adapter ||= resolve_adapter
      end

      def adapter=(adapter_instance)
        @adapter = adapter_instance
      end

      def reset!
        @adapter = nil
      end

      private

      def resolve_adapter
        adapter_class = Rails.application.config.kyc_inference_adapter
        adapter_class = adapter_class.constantize if adapter_class.is_a?(String)
        adapter_class.new
      end
    end
  end
end
