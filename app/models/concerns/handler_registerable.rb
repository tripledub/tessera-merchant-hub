# frozen_string_literal: true

module HandlerRegisterable
  class NoHandlerAccepted < StandardError
    def message
      "No Handler Accepted"
    end
  end

  def registered_handlers
    @registered_handlers ||= {}
  end

  def obtain(condition)
    handlers = registered_handlers
    handlers = handlers.to_a.reverse.to_h if handlers.present?

    handlers.each_value do |handler|
      return handler.new(condition) if handler.handles?(condition)
    end

    if @default
      @default.new(condition)
    else
      raise NoHandlerAccepted
    end
  end

  attr_accessor :default
end
