import { Controller } from "@hotwired/stimulus"

// Hides the trading-address fieldset while "same as registered address" is
// checked, so the applicant isn't shown what looks like a duplicate, blank
// address block. The server mirrors the registered address into the
// trading address on save regardless of whether JS ran.
export default class extends Controller {
  static targets = ["checkbox", "fields"]

  connect() {
    this.toggle()
  }

  toggle() {
    const hide = this.checkboxTarget.checked
    this.fieldsTarget.hidden = hide
    // Hiding alone doesn't exempt required fields from constraint validation in
    // every browser — a required-but-hidden field can silently block submission
    // with no visible feedback. Disabling removes it from validation and submission.
    this.fieldsTarget.querySelectorAll("input, select, textarea").forEach((field) => {
      field.disabled = hide
    })
  }
}
