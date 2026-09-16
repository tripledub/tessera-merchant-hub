import { Controller } from "@hotwired/stimulus"

// Scrolls a target element into view without touching location.hash — a
// plain <a href="#id"> would collide with tabs_controller, which reads
// window.location.hash to decide which tab panel is active.
export default class extends Controller {
  static values = { target: String }

  jump() {
    document.getElementById(this.targetValue)?.scrollIntoView({ behavior: "smooth", block: "start" })
  }
}
