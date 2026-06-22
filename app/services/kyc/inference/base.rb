# frozen_string_literal: true

module Kyc
  module Inference
    class Base
      def extract_group_structure(document)
        raise NotImplementedError, "#{self.class}#extract_group_structure must be implemented"
      end
    end
  end
end
