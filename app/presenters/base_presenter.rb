# frozen_string_literal: true

class BasePresenter
  def initialize(object, template)
    @object = object
    @template = template
  end

  def self.presents(name)
    define_method(name) do
      @object
    end
  end

  def method_missing(method, ...)
    if @template.respond_to?(method)
      @template.send(method, ...)
    else
      super
    end
  end

  def respond_to_missing?(method, include_private = false)
    @template.respond_to?(method, include_private) || super
  end
end
