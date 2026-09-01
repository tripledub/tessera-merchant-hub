import { Controller } from "@hotwired/stimulus"

// Fills the applicant Name field with the registry-found company name while
// the "Use these details" checkbox is checked. Applied on connect/toggle
// (rather than on submit) because native HTML5 required-field validation
// runs before the form's submit event fires, so a fill deferred to submit
// would never take effect when Name starts out empty.
export default class extends Controller {
  static values = { companyName: String }
  static targets = ["checkbox"]

  connect() {
    if (this.checkboxTarget.checked) this.apply()
  }

  toggle() {
    if (this.checkboxTarget.checked) this.apply()
  }

  apply() {
    const nameField = this.element.closest("form")?.querySelector("#applicant_name")
    if (nameField) nameField.value = this.companyNameValue
  }
}
