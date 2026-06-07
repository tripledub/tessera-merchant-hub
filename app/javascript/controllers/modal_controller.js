// app/javascript/controllers/modal_controller.js
// Manages a Turbo Frame modal: scroll lock, Escape/backdrop close.
// Usage:
//   <div data-controller="modal" data-action="keydown.esc@window->modal#close">
//     <div data-action="click->modal#close"><!-- backdrop --></div>
//     <!-- modal card — stop propagation so clicks inside don't close -->
//   </div>
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    document.body.style.overflow = "hidden"
  }

  disconnect() {
    document.body.style.overflow = ""
  }

  close() {
    const frame = document.getElementById("payment-modal")
    if (frame) {
      frame.src = ""
      frame.innerHTML = ""
    }
  }
}
