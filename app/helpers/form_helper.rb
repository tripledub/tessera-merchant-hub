# frozen_string_literal: true

module FormHelper
  def field_class(resource, attribute)
    resource.errors[attribute].any? ? "form-input-error" : "form-input"
  end

  def field_error(resource, attribute)
    return if resource.errors[attribute].blank?

    content_tag(:p, resource.errors.full_messages_for(attribute).first, class: "form-error")
  end
end
