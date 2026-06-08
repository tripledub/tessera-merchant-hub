import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "panelToggle"]

  // Called by selects and checkboxes via data-action="change->filter#submit"
  submit() {
    this.element.requestSubmit()
  }

  // Called by text and number inputs via data-action="input->filter#submitDebounced"
  // Waits 400ms after the last keystroke before submitting.
  submitDebounced() {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this.submit(), 400)
  }

  // Toggles the filter panel open/closed.
  // Called by the "Filters" button via data-action="click->filter#togglePanel"
  togglePanel() {
    const hidden = this.panelTarget.classList.toggle("hidden")
    this.panelToggleTarget.setAttribute("aria-expanded", (!hidden).toString())
  }
}
