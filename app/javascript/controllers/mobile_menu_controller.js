import { Controller } from "@hotwired/stimulus"

// Toggles the mobile navigation drawer.
// Usage:
//   <nav data-controller="mobile-menu">
//     <button data-action="mobile-menu#toggle" aria-expanded="false">…</button>
//     <div data-mobile-menu-target="panel" hidden>…</div>
//   </nav>
export default class extends Controller {
  static targets = ["panel", "button"]

  toggle() {
    const expanded = !this.panelTarget.hidden
    this.panelTarget.hidden = expanded
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", String(!expanded))
    }
  }

  close() {
    this.panelTarget.hidden = true
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "false")
    }
  }
}
