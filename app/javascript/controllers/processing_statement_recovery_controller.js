import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "status", "map", "remap", "remove" ]

  connect() {
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.sync()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  sync() {
    const status = this.statusTarget?.dataset.status
    if (this.hasMapTarget) this.mapTarget.hidden = status !== "uploaded"
    if (this.hasRemapTarget) this.remapTarget.hidden = status !== "error"
    if (this.hasRemoveTarget) this.removeTarget.hidden = status !== "error"
  }
}
