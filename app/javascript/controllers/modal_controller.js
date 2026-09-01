import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { frame: String }

  connect() {
    document.body.style.overflow = "hidden"

    const frame = this.frameElement
    const isFirstOpen = frame && !frame.dataset.modalReturnFocusSet
    if (isFirstOpen) {
      frame._modalReturnFocus = document.activeElement
      frame.dataset.modalReturnFocusSet = "true"

      const focusTarget = this.element.querySelector("textarea") || this.element.querySelector("button, [href], input, select")
      focusTarget?.focus()
    }
  }

  disconnect() {
    document.body.style.overflow = ""
  }

  close() {
    const frame = this.frameElement
    if (frame) {
      const returnFocus = frame._modalReturnFocus
      frame.src = ""
      frame.innerHTML = ""
      delete frame.dataset.modalReturnFocusSet
      if (returnFocus && document.contains(returnFocus)) returnFocus.focus()
    }
  }

  get frameElement() {
    const frameId = this.hasFrameValue ? this.frameValue : "payment-modal"
    return document.getElementById(frameId)
  }
}
