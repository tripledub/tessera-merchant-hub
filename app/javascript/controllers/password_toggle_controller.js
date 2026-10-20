import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "showIcon", "hideIcon", "button"]
  static values = {
    showLabel: { type: String, default: "Show password" },
    hideLabel: { type: String, default: "Hide password" }
  }

  toggle() {
    const isPassword = this.inputTarget.type === "password"
    this.inputTarget.type = isPassword ? "text" : "password"
    this.showIconTarget.classList.toggle("hidden", !isPassword)
    this.hideIconTarget.classList.toggle("hidden", isPassword)

    // Report the new state to assistive tech: pressed while the password is visible.
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-pressed", String(isPassword))
      this.buttonTarget.setAttribute("aria-label", isPassword ? this.hideLabelValue : this.showLabelValue)
    }
  }
}
