# frozen_string_literal: true

module Shops
  class UpdateSettings
    PERMITTED = %i[display_name notification_url test_mode].freeze
    private_constant :PERMITTED

    def self.call(shop, params) = new(shop, params).call

    def initialize(shop, params)
      @shop   = shop
      @params = params.to_h.symbolize_keys.slice(*PERMITTED)
      if @params.key?(:test_mode)
        @params[:test_mode] = ActiveModel::Type::Boolean.new.cast(@params[:test_mode])
      end
    end

    def call
      @shop.update(@params)
      @shop
    end
  end
end
