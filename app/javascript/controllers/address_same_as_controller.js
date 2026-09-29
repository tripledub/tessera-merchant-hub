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
    this.fieldsTarget.hidden = this.checkboxTarget.checked
  }
}
