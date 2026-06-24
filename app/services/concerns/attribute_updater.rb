# frozen_string_literal: true

# Shared base for simple service objects that filter permitted attributes and
# update a single record. Subclasses define PERMITTED and optionally override
# #coerce_params to cast values before persistence.
#
#   class MyService
#     include AttributeUpdater
#     PERMITTED = %i[name email].freeze
#   end
#
#   MyService.call(record, params)
module AttributeUpdater
  extend ActiveSupport::Concern

  class_methods do
    def call(record, params) = new(record, params).call

    def permitted_attributes
      const_get(:PERMITTED)
    end
  end

  def initialize(record, params)
    @record = record
    @params = params.to_h.symbolize_keys.slice(*self.class.permitted_attributes)
    coerce_params
  end

  def call
    @record.update(@params)
    @record
  end

  private

  def coerce_params; end
end
