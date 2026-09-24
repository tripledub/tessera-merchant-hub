import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    document.addEventListener("click", this.boundClickOutside = (event) => {
      if (!this.element.contains(event.target)) this.close()
    })
    document.addEventListener("keydown", this.boundEscape = (event) => {
      if (event.key === "Escape") this.close()
    })
    // MH-336: the Documents panel wraps its row list in overflow-hidden for
    // its single-bounding-box look — an absolutely-positioned dropdown for
    // the last row in a panel runs past that clipped edge and gets cut off.
    // Reposition (or just close, on resize) keeps a fixed-position menu
    // anchored to its trigger instead of drifting or clipping again.
    window.addEventListener("scroll", this.boundReposition = () => this.reposition(), true)
    window.addEventListener("resize", this.boundClose = () => this.close())
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    document.removeEventListener("keydown", this.boundEscape)
    window.removeEventListener("scroll", this.boundReposition, true)
    window.removeEventListener("resize", this.boundClose)
  }

  toggle(event) {
    event.stopPropagation()
    const opening = this.menuTarget.classList.contains("hidden")
    this.menuTarget.classList.toggle("hidden")
    if (opening) this.reposition()
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }

  // Fixed positioning computed from the trigger's live bounding rect
  // escapes any overflow-hidden ancestor entirely, rather than assuming a
  // downward-opening dropdown always has room within its container.
  reposition() {
    if (this.menuTarget.classList.contains("hidden")) return

    const rect = this.buttonTarget.getBoundingClientRect()
    this.menuTarget.style.position = "fixed"
    this.menuTarget.style.top = `${rect.bottom + 4}px`
    this.menuTarget.style.right = `${window.innerWidth - rect.right}px`
    this.menuTarget.style.left = "auto"
  }
}
