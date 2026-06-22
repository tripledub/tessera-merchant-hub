# frozen_string_literal: true

module Kyc
  module Inference
    class Base
      def extract(document:, prompt:)
        raise NotImplementedError, "#{self.class}#extract must be implemented"
      end
    end
  end
end
