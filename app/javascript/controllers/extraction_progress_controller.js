import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "counter", "label"]
  static values = { total: Number }

  connect() {
    this.recalculate()
    document.addEventListener("turbo:before-stream-render", this.boundRecalculate = () => {
      setTimeout(() => this.recalculate(), 100)
    })
  }

  disconnect() {
    if (this.boundRecalculate) {
      document.removeEventListener("turbo:before-stream-render", this.boundRecalculate)
    }
  }

  recalculate() {
    if (this.totalValue === 0) return

    const cards = document.querySelectorAll("[id^='kyc_document_']")
    let done = 0
    cards.forEach(card => {
      if (card.textContent.includes("Complete") || card.textContent.includes("Error")) done++
    })

    const pct = Math.round((done / this.totalValue) * 100)

    if (this.hasBarTarget) this.barTarget.style.width = `${pct}%`
    if (this.hasCounterTarget) this.counterTarget.textContent = `${done} of ${this.totalValue}`

    if (done >= this.totalValue && this.hasLabelTarget) {
      this.labelTarget.textContent = "Extraction complete"
      if (this.hasBarTarget) {
        this.barTarget.classList.remove("bg-brand-500")
        this.barTarget.classList.add("bg-green-500")
      }
    }
  }
}
