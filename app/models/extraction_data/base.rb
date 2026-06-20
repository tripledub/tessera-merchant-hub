# frozen_string_literal: true

module ExtractionData
  class Base
    include StoreModel::Model

    def self.for(document_type)
      load_all_models
      registry.fetch(document_type.to_s, ExtractionData::Generic)
    end

    def self.load_all_models
      return if @loaded

      Dir[File.join(__dir__, "*.rb")].each { |f| require f }
      @loaded = true
    end

    def self.registry
      @registry ||= {}
    end

    def self.register_as(document_type)
      ExtractionData::Base.registry[document_type.to_s] = self
    end
  end
end
