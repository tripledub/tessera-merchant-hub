import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "counter", "label"]
  static values = { total: Number }

  connect() {
    this.completed = 0
    this.observer = new MutationObserver(() => this.recalculate())

    const docList = document.querySelector(".space-y-2")
    if (docList) {
      this.observer.observe(docList, { childList: true, subtree: true, attributes: true })
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  recalculate() {
    // Count documents with Complete or Error badges
    const cards = document.querySelectorAll("[id^='kyc_document_']")
    let done = 0
    cards.forEach(card => {
      const text = card.textContent
      if (text.includes("Complete") || text.includes("Error")) done++
    })

    // Only update if we're actually tracking (total > 0)
    if (this.totalValue === 0) return

    this.completed = done
    const pct = Math.round((done / this.totalValue) * 100)

    this.barTarget.style.width = `${pct}%`
    this.counterTarget.textContent = `${done} of ${this.totalValue}`

    if (done >= this.totalValue) {
      this.labelTarget.textContent = "Extraction complete"
      this.barTarget.classList.remove("bg-brand-500")
      this.barTarget.classList.add("bg-green-500")
    }
  }
}
