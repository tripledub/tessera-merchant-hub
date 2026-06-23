import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { dismissAfter: { type: Number, default: 5000 } }

  connect() {
    // Slide in
    requestAnimationFrame(() => {
      this.element.classList.remove("translate-x-full", "opacity-0")
    })

    // Auto-dismiss
    if (this.dismissAfterValue > 0) {
      this.timeout = setTimeout(() => this.dismiss(), this.dismissAfterValue)
    }
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("opacity-0")
    this.element.style.transition = "opacity 300ms ease-out"
    setTimeout(() => this.element.remove(), 300)
  }
}
