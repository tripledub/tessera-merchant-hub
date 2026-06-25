import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.element.setAttribute("novalidate", "")
    this.element.addEventListener("blur", this.validateField.bind(this), true)
  }

  submitForm(event) {
    const fields = this.element.querySelectorAll("input[required], input[type='email']")
    let valid = true

    fields.forEach((field) => {
      if (!this.isValid(field)) {
        this.showError(field)
        valid = false
      }
    })

    if (!valid) event.preventDefault()
  }

  validateField(event) {
    const field = event.target
    if (field.tagName !== "INPUT") return

    if (this.isValid(field)) {
      this.clearError(field)
    } else if (field.value.length > 0 || field.dataset.touched) {
      this.showError(field)
    }

    field.dataset.touched = "true"
  }

  isValid(field) {
    if (field.required && !field.value.trim()) return false
    if (field.type === "email" && field.value && !field.value.match(/^[^@\s]+@[^@\s]+\.[^@\s]+$/)) return false
    if (field.minLength > 0 && field.value.length < field.minLength) return false
    if (field.type === "password" && field.name.includes("confirmation")) {
      const password = this.element.querySelector("input[name*='password']:not([name*='confirmation'])")
      if (password && field.value !== password.value) return false
    }
    return true
  }

  showError(field) {
    field.classList.remove("form-input")
    field.classList.add("form-input-error")

    let msg = this.errorMessage(field)
    let errorEl = field.closest("div").querySelector(".form-error")

    if (!errorEl) {
      errorEl = document.createElement("p")
      errorEl.classList.add("form-error")
      const wrapper = field.closest("[data-controller='password-toggle']") || field.parentElement
      wrapper.parentElement.appendChild(errorEl)
    }

    errorEl.textContent = msg
  }

  clearError(field) {
    field.classList.remove("form-input-error")
    field.classList.add("form-input")

    const errorEl = field.closest("div").parentElement?.querySelector(".form-error")
    if (errorEl) errorEl.remove()
  }

  errorMessage(field) {
    if (field.required && !field.value.trim()) {
      return `${this.labelText(field)} is required`
    }
    if (field.type === "email") return "Please enter a valid email address"
    if (field.minLength > 0 && field.value.length < field.minLength) {
      return `Must be at least ${field.minLength} characters`
    }
    if (field.name.includes("confirmation")) return "Passwords don't match"
    return "Invalid value"
  }

  labelText(field) {
    const label = this.element.querySelector(`label[for='${field.id}']`)
    return label?.textContent?.trim() || "This field"
  }
}
