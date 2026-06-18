import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { frame: String }

  connect() {
    document.body.style.overflow = "hidden"
  }

  disconnect() {
    document.body.style.overflow = ""
  }

  close() {
    const frameId = this.hasFrameValue ? this.frameValue : "payment-modal"
    const frame = document.getElementById(frameId)
    if (frame) {
      frame.src = ""
      frame.innerHTML = ""
    }
  }
}
