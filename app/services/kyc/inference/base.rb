# frozen_string_literal: true

module Kyc
  module Inference
    class Base
      def extract(document:, prompt:, schema: nil)
        raise NotImplementedError, "#{self.class}#extract must be implemented"
      end

      def generate(prompt:, schema: nil, stream: false, &block)
        raise NotImplementedError, "#{self.class}#generate must be implemented"
      end
    end
  end
end
