import { Controller } from "@hotwired/stimulus"

// Masks the edges of a horizontally scrollable element to fade out content
// that continues off-screen, so overflow is visually obvious even when the
// native scrollbar is invisible or hard to notice (e.g. on mobile).
export default class extends Controller {
  static values = { size: { type: Number, default: 24 } }

  connect() {
    this.update = this.update.bind(this)
    this.update()
    window.addEventListener("resize", this.update)
  }

  disconnect() {
    window.removeEventListener("resize", this.update)
  }

  update() {
    const el = this.element
    const canScrollLeft = el.scrollLeft > 1
    const canScrollRight = el.scrollLeft + el.clientWidth < el.scrollWidth - 1

    const fade = `${this.sizeValue}px`
    let mask = "none"
    if (canScrollLeft && canScrollRight) {
      mask = `linear-gradient(to right, transparent, black ${fade}, black calc(100% - ${fade}), transparent)`
    } else if (canScrollRight) {
      mask = `linear-gradient(to right, black calc(100% - ${fade}), transparent)`
    } else if (canScrollLeft) {
      mask = `linear-gradient(to left, black calc(100% - ${fade}), transparent)`
    }

    el.style.maskImage = mask
    el.style.webkitMaskImage = mask
  }
}
