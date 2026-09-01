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
      // than silently letting it fall back to document.body. A response can
      // opt a specific element into this via data-modal-autofocus (e.g. an
      // invalid field on a validation failure) — that takes priority over
      // the generic "selected toggle" guess, which only fits state-toggle
      // responses like a status button.
      const focusTarget =
        this.element.querySelector("[data-modal-autofocus]") ||
        this.element.querySelector('[aria-pressed="true"]') ||
        this.element.querySelector("textarea") ||
        this.element.querySelector("button, [href], input, select")
      focusTarget?.focus()
    }
  }

  disconnect() {
    document.body.style.overflow = ""

    // Stimulus batches connect/disconnect per mutation, so by the time this
    // runs the frame has already settled into its final DOM state. If a
    // fresh modal instance is already there, this disconnect is just the
    // old instance being swapped out mid-open (a re-render, e.g. a status
    // toggle or a validation retry) — leave the saved return-focus/state
    // alone, the new instance still needs it. Only clean up when the frame
    // ends up with no modal content at all: that's a genuine close,
    // whether triggered by close() below or by a server response emptying
    // the frame directly (e.g. a turbo_stream.update to "" on success).
    const frame = this.frameElement
    if (frame && !frame.querySelector('[data-controller~="modal"]')) {
      const returnFocusId = frame.dataset.modalReturnFocusTriggerId
      const returnFocusElement = frame._modalReturnFocusElement
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

  close() {
    const frame = this.frameElement
    if (frame) {
      frame.src = ""
      frame.innerHTML = ""
    }
  }

  get frameElement() {
    const frameId = this.hasFrameValue ? this.frameValue : "payment-modal"
    return document.getElementById(frameId)
  }
}
