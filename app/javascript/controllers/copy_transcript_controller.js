import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { copiedLabel: String }

  copy() {
    const text = document.getElementById("transcript-plain-text").textContent
    navigator.clipboard.writeText(text)

    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = this.copiedLabelValue

    setTimeout(() => {
      this.buttonTarget.textContent = original
    }, 1500)
  }
}
