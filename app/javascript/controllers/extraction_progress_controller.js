import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "counter", "label"]
  static values = { total: Number }

  connect() {
    this.baselineComplete = this.countComplete()
    this.update(0)

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
    const newlyDone = this.countComplete() - this.baselineComplete
    this.update(Math.max(0, newlyDone))
  }

  update(done) {
    const pct = this.totalValue > 0 ? Math.round((done / this.totalValue) * 100) : 0

    if (this.hasBarTarget) this.barTarget.style.width = `${pct}%`
    if (this.hasCounterTarget) this.counterTarget.textContent = `${done} of ${this.totalValue}`

    if (done >= this.totalValue && done > 0 && this.hasLabelTarget) {
      this.labelTarget.textContent = "Extraction complete"
      if (this.hasBarTarget) {
        this.barTarget.classList.remove("bg-brand-500")
        this.barTarget.classList.add("bg-green-500")
      }
    }
  }

  countComplete() {
    let count = 0
    document.querySelectorAll("[id^='kyc_document_']").forEach(card => {
      if (card.textContent.includes("Complete") || card.textContent.includes("Error")) count++
    })
    return count
  }
}
