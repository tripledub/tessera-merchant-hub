# frozen_string_literal: true

module Shops
  class UpdateSettings
    include AttributeUpdater

    PERMITTED = %i[display_name notification_url test_mode].freeze
    private_constant :PERMITTED

    private

    def coerce_params
      if @params.key?(:test_mode)
        @params[:test_mode] = ActiveModel::Type::Boolean.new.cast(@params[:test_mode])
      end
    end
  end
end
