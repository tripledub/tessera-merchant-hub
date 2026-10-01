import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "feedback"]
  static values = { success: { type: String, default: "Copied!" } }

  selectAll() {
    this.sourceTarget.select()
  }

  async copy() {
    const text = "value" in this.sourceTarget ? this.sourceTarget.value : this.sourceTarget.textContent.trim()
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
