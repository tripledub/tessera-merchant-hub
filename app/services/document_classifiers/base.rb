# frozen_string_literal: true

module DocumentClassifiers
  class Base
    def self.register(handler:)
      DocumentClassifiers.registered_handlers[handler] = self
    end

    def self.handles?(condition)
      pattern.match?(condition.filename.downcase)
    end

    def self.pattern
      raise NotImplementedError, "#{name} must implement .pattern"
    end

    attr_reader :condition

    def initialize(condition)
      @condition = condition
    end

    def document_type
      self.class.name.demodulize.underscore.to_sym
    end

    def classification_method
      :rule_based
    end

    def classify
      {
        document_type: document_type,
        classification_method: classification_method,
        confidence: 1.0
      }
    end
  end
end
