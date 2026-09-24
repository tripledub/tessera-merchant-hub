import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "counter", "label"]
  static values = { documentIds: Array }

  connect() {
    this.update(this.countComplete())

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
    this.update(this.countComplete())
  }

  update(done) {
    const total = this.documentIdsValue.length
    const pct = total > 0 ? Math.round((done / total) * 100) : 0

    if (this.hasBarTarget) this.barTarget.style.width = `${pct}%`
    if (this.hasCounterTarget) this.counterTarget.textContent = `${done} of ${total}`

    if (done >= total && done > 0 && this.hasLabelTarget) {
      this.labelTarget.textContent = "Extraction complete"
      if (this.hasBarTarget) {
        this.barTarget.classList.remove("bg-brand-500")
        this.barTarget.classList.add("bg-green-500")
      }
    }
  }

  // Only the content div — the single element that actually carries the
  // document's current status text — is queried per id, and only for the
  // ids this run queued, so a document already Complete/Error elsewhere on
  // the Documents tab (or the same document's other nested elements, e.g.
  // its turbo-frame or metadata div) can never inflate the count.
  countComplete() {
    let count = 0
    this.documentIdsValue.forEach(id => {
      const content = document.getElementById(`kyc_document_${id}_content`)
      if (content && (content.textContent.includes("Complete") || content.textContent.includes("Error"))) count++
    })
    return count
  }
}
