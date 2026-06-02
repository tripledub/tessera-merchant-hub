import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "feedback"]
  static values = { success: { type: String, default: "Copied!" } }

  async copy() {
    const text = this.sourceTarget.textContent.trim()
    try {
      await navigator.clipboard.writeText(text)
      if (this.hasFeedbackTarget) {
        this.feedbackTarget.textContent = this.successValue
        setTimeout(() => { this.feedbackTarget.textContent = "" }, 2000)
      }
    } catch (_error) {
      if (this.hasFeedbackTarget) {
        this.feedbackTarget.textContent = "Copy failed"
      }
    }
  }
}
