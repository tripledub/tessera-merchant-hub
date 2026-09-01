import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { frame: String }

  connect() {
    document.body.style.overflow = "hidden"

    const frame = this.frameElement
    const isFirstOpen = frame && !frame.dataset.modalReturnFocusSet
    if (isFirstOpen) {
      const activeElement = document.activeElement
      frame.dataset.modalReturnFocusTriggerId = activeElement?.id || ""
      frame._modalReturnFocusElement = activeElement
      frame.dataset.modalReturnFocusSet = "true"

      const focusTarget = this.element.querySelector("textarea") || this.element.querySelector("button, [href], input, select")
      focusTarget?.focus()
    } else if (frame && !this.element.contains(document.activeElement)) {
      // Inner-content update (e.g. a turbo_stream.update) replaced whatever
      // was focused. Reassign focus within the newly-rendered content rather
      // than silently letting it fall back to document.body.
      const focusTarget =
        this.element.querySelector('[aria-pressed="true"]') ||
        this.element.querySelector("textarea") ||
        this.element.querySelector("button, [href], input, select")
      focusTarget?.focus()
    }
  }

  disconnect() {
    document.body.style.overflow = ""
  }

  close() {
    const frame = this.frameElement
    if (frame) {
      const returnFocusId = frame.dataset.modalReturnFocusTriggerId
      const returnFocusElement = frame._modalReturnFocusElement
      frame.src = ""
      frame.innerHTML = ""
      delete frame.dataset.modalReturnFocusSet
      delete frame.dataset.modalReturnFocusTriggerId
      delete frame._modalReturnFocusElement

      const byId = returnFocusId ? document.getElementById(returnFocusId) : null
      if (byId) {
        byId.focus()
      } else if (returnFocusElement && document.contains(returnFocusElement)) {
        returnFocusElement.focus()
      }
    }
  }

  get frameElement() {
    const frameId = this.hasFrameValue ? this.frameValue : "payment-modal"
    return document.getElementById(frameId)
  }
}
