import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "panelToggle", "badge"]

  connect() {
    // When a chip or "Clear all" updates only the turbo-frame, the URL changes
    // but form inputs outside the frame keep stale values. Sync them from the URL.
    this._onFrameLoad = () => this._syncFromUrl()
    document.addEventListener("turbo:frame-load", this._onFrameLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this._onFrameLoad)
  }

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

  // Reads current URL search params and updates all panel inputs to match.
  // Called after turbo:frame-load so chips and "Clear all" stay in sync.
  _syncFromUrl() {
    const params = new URLSearchParams(window.location.search)

    // Number and text inputs
    ;["amount_min", "amount_max", "reference"].forEach(name => {
      const input = this.element.querySelector(`[name="${name}"]`)
      if (input) input.value = params.get(name) ?? ""
    })

    // Status checkboxes — name is "status[]"
    const activeStatuses = params.getAll("status[]")
    this.element.querySelectorAll('[name="status[]"]').forEach(cb => {
      cb.checked = activeStatuses.includes(cb.value)
    })

    // Date fields
    ;["date_from", "date_to"].forEach(name => {
      const input = this.element.querySelector(`[name="${name}"]`)
      if (input) input.value = params.get(name) ?? ""
    })

    // Update the active-filter count badge on the Filters button
    const count = ["status[]", "date_from", "date_to", "amount_min", "amount_max"]
      .reduce((n, key) => {
        const vals = key === "status[]" ? params.getAll(key) : [params.get(key)].filter(Boolean)
        return n + (vals.length > 0 ? 1 : 0)
      }, 0)

    if (this.hasBadgeTarget) {
      this.badgeTarget.textContent = count
      this.badgeTarget.classList.toggle("hidden", count === 0)
    }
  }
}
