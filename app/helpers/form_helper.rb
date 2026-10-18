# frozen_string_literal: true

module FormHelper
  def field_class(resource, attribute)
    resource.errors[attribute].any? ? "form-input-error" : "form-input"
  end

  def field_error(resource, attribute)
    return if resource.errors[attribute].blank?

    content_tag(:p, resource.errors.full_messages_for(attribute).first, class: "form-error")
  end

  # MH-395: applicant twins. kyn-input styles its error state from aria-invalid
  # (the same attribute form_validation_controller.js sets), so the class never
  # changes: use kyn_field_aria to mark an invalid field server-side.
  def kyn_field_class(_resource, _attribute)
    "kyn-input"
  end

  def kyn_field_aria(resource, attribute, error_id)
    return {} if resource.errors[attribute].blank?

    { "aria-invalid": "true", "aria-describedby": error_id }
  end

  # Same markup the validation controller creates, so the kyn-field wrapper
  # restyles both.
  def kyn_field_error(resource, attribute, id: nil)
    return if resource.errors[attribute].blank?

    content_tag(:p, resource.errors.full_messages_for(attribute).first,
                id: id, class: "form-error", data: { form_validation_error: "" })
  end
end
