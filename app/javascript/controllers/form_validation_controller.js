import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.setAttribute("novalidate", "")
    this.element.addEventListener("blur", this.handleBlur.bind(this), true)
    this.element.addEventListener("change", this.handleChange.bind(this), true)
  }

  submitForm(event) {
    let valid = true
    let firstInvalid = null

    this.candidateFields().forEach((field) => {
      field.dataset.touched = "true"

      if (this.isValid(field)) {
        this.clearError(field)
      } else {
        this.showError(field)
        valid = false
        firstInvalid ||= field
      }
    })

    if (!valid) {
      event.preventDefault()
      firstInvalid?.focus()
    }
  }

  handleBlur(event) {
    const field = event.target
    if (!this.isCandidate(field)) return

    field.dataset.touched = "true"
    this.isValid(field) ? this.clearError(field) : this.showError(field)
  }

  handleChange(event) {
    const field = event.target
    if (!this.isCandidate(field) || !["radio", "checkbox", "select-one"].includes(field.type)) return

    this.groupFor(field).forEach((related) => {
      related.dataset.touched = "true"
      this.isValid(related) ? this.clearError(related) : this.showError(related)
    })
  }

  // Deliberately scoped to non-repeatable fields for now — fields inside a
  // repeatable-fields group (dynamically added/removed rows) still rely on
  // native browser validation until that's covered in a follow-up.
  candidateFields() {
    return Array.from(this.element.querySelectorAll("input[required], textarea[required], select[required]"))
      .filter((field) => this.isCandidate(field))
  }

  isCandidate(field) {
    return !field.disabled && !field.closest("[data-controller~='repeatable-fields']")
  }

  isValid(field) {
    if (!field.checkValidity()) return false
    if (field.type === "password" && field.name.includes("confirmation")) {
      const password = this.element.querySelector("input[name*='password']:not([name*='confirmation'])")
      if (password && field.value !== password.value) return false
    }
    return true
  }

  groupFor(field) {
    if (field.type !== "radio") return [field]
    return Array.from(this.element.querySelectorAll(`input[type='radio'][name='${field.name}']`))
  }

  showError(field) {
    if (field.type === "radio") {
      this.showRadioGroupError(field)
      return
    }

    field.classList.remove("form-input")
    field.classList.add("form-input-error")
    field.setAttribute("aria-invalid", "true")

    const errorEl = this.errorElementFor(field)
    errorEl.textContent = this.errorMessage(field)
    field.setAttribute("aria-describedby", errorEl.id)
  }

  clearError(field) {
    if (field.type === "radio") {
      this.clearRadioGroupError(field)
      return
    }

    field.classList.remove("form-input-error")
    field.classList.add("form-input")
    field.removeAttribute("aria-invalid")
    field.removeAttribute("aria-describedby")

    this.errorElementFor(field, { create: false })?.remove()
  }

  showRadioGroupError(field) {
    const fieldset = field.closest("fieldset")
    this.groupFor(field).forEach((radio) => radio.setAttribute("aria-invalid", "true"))
    fieldset?.classList.add("fieldset-error")

    const errorEl = this.errorElementFor(field, { container: fieldset })
    errorEl.textContent = this.errorMessage(field)
    this.groupFor(field).forEach((radio) => radio.setAttribute("aria-describedby", errorEl.id))
  }

  clearRadioGroupError(field) {
    const fieldset = field.closest("fieldset")
    this.groupFor(field).forEach((radio) => {
      radio.removeAttribute("aria-invalid")
      radio.removeAttribute("aria-describedby")
    })
    fieldset?.classList.remove("fieldset-error")

    this.errorElementFor(field, { container: fieldset, create: false })?.remove()
  }

  errorElementFor(field, { container, create = true } = {}) {
    const scope = container || this.fieldContainer(field)
    let errorEl = scope.querySelector(":scope > .form-error, :scope > [data-form-validation-error]")

    if (!errorEl && create) {
      errorEl = document.createElement("p")
      errorEl.classList.add("form-error")
      errorEl.setAttribute("data-form-validation-error", "")
      errorEl.id = `${field.name.replace(/[^\w-]/g, "_")}-error`
      scope.appendChild(errorEl)
    }

    return errorEl
  }

  fieldContainer(field) {
    return field.closest("[data-field]") || field.closest("div:not([data-controller])")?.parentElement || field.parentElement
  }

  errorMessage(field) {
    const validity = field.validity

    if (validity.valueMissing) {
      return field.type === "radio" ? "Please select an option" : `${this.labelText(field)} is required`
    }
    if (validity.typeMismatch && field.type === "email") return "Please enter a valid email address"
    if (validity.tooShort) return `Must be at least ${field.minLength} characters`
    if (validity.rangeUnderflow) return `Must be at least ${field.min}`
    if (validity.rangeOverflow) return `Must be at most ${field.max}`
    if (field.type === "password" && field.name.includes("confirmation")) return "Passwords don't match"
    return field.validationMessage || "Invalid value"
  }

  labelText(field) {
    const label = this.element.querySelector(`label[for='${field.id}']`)
    return label?.textContent?.trim() || "This field"
  }
}
