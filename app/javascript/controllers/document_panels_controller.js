import { Controller } from "@hotwired/stimulus"

// MH-302: keeps each document row in the right Documents-tab panel
// (Unconfirmed / Confirmed / Processed) as its status changes live.
//
// A document's row (the turbo-frame wrapping kyc/documents/_kyc_document) never
// moves itself — moving it would mean re-rendering the full row from a
// background job broadcast, which KycDocumentBroadcaster deliberately avoids
// (see its comment: Pundit-gated content has no real viewer to authorize
// against outside a request). Instead, only the safely-broadcastable metadata
// partial is replaced in place, and it carries a small `data-status-group`
// marker with the document's current panel. This controller watches for any
// turbo stream render (create, confirm, extract, retry, destroy — they all go
// through the same applicant_#{id}_documents stream) and reconciles: moves
// each row's *already-rendered* DOM node into the panel matching its current
// marker, then updates each panel's visible/hidden state and count.
export default class extends Controller {
  static targets = ["panel", "list", "count"]

  connect() {
    this.reconcile()
    document.addEventListener("turbo:before-stream-render", this.boundReconcile = () => {
      setTimeout(() => this.reconcile(), 50)
    })
  }

  disconnect() {
    if (this.boundReconcile) {
      document.removeEventListener("turbo:before-stream-render", this.boundReconcile)
    }
  }

  reconcile() {
    this.listTargets.forEach((list) => {
      const group = list.dataset.group

      this.element.querySelectorAll(`[data-status-group="${group}"]`).forEach((marker) => {
        const row = marker.closest("[data-document-row]")
        if (row && row.parentElement !== list) list.appendChild(row)
      })
    })

    this.panelTargets.forEach((panel) => {
      const list = panel.querySelector("[data-document-panels-target~='list']")
      const count = list ? list.children.length : 0
      const counter = panel.querySelector("[data-document-panels-target~='count']")

      panel.classList.toggle("hidden", count === 0)
      if (counter) counter.textContent = `(${count})`
    })
  }
}
