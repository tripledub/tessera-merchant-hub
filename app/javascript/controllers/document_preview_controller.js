import { Controller } from "@hotwired/stimulus"

const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"]

export default class extends Controller {
  static values = {
    url: String,
    contentType: String
  }

  connect() {
    if (this.isImage) {
      this.element.addEventListener("mouseenter", this.showThumbnail)
      this.element.addEventListener("mouseleave", this.hideThumbnail)
      this.element.style.cursor = "pointer"
    }
  }

  disconnect() {
    this.hideThumbnail()
    this.element.removeEventListener("mouseenter", this.showThumbnail)
    this.element.removeEventListener("mouseleave", this.hideThumbnail)
  }

  open(event) {
    if (this.isImage) {
      this.openImageModal()
    } else if (this.isPdf) {
      this.openPdfModal()
    }
  }

  // private

  get isImage() {
    return IMAGE_TYPES.includes(this.contentTypeValue)
  }

  get isPdf() {
    return this.contentTypeValue === "application/pdf"
  }

  showThumbnail = () => {
    const existing = document.getElementById("doc-preview-thumbnail")
    if (existing) existing.remove()

    const tip = document.createElement("div")
    tip.id = "doc-preview-thumbnail"
    tip.className = "fixed z-50 rounded-lg shadow-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-1 pointer-events-none"
    tip.style.maxWidth = "220px"

    const img = document.createElement("img")
    img.src = this.urlValue
    img.className = "rounded max-w-full max-h-48 object-contain"
    tip.appendChild(img)
    document.body.appendChild(tip)

    this.positionThumbnail(tip)
    this._thumbnail = tip
  }

  hideThumbnail = () => {
    const tip = document.getElementById("doc-preview-thumbnail")
    if (tip) tip.remove()
    this._thumbnail = null
  }

  positionThumbnail(tip) {
    const rect = this.element.getBoundingClientRect()
    const scrollY = window.scrollY || document.documentElement.scrollTop
    const scrollX = window.scrollX || document.documentElement.scrollLeft

    let top = rect.bottom + scrollY + 8
    let left = rect.left + scrollX

    // Flip above if too close to bottom
    if (rect.bottom + 220 > window.innerHeight) {
      top = rect.top + scrollY - 220 - 8
    }

    tip.style.top = `${top}px`
    tip.style.left = `${left}px`
  }

  openImageModal() {
    this.openModal(`<img src="${this.urlValue}" class="max-w-full max-h-screen object-contain rounded" />`)
  }

  openPdfModal() {
    this.openModal(`<iframe src="${this.urlValue}" class="w-full h-full rounded" style="min-height:80vh;"></iframe>`)
  }

  openModal(content) {
    const existing = document.getElementById("doc-preview-modal")
    if (existing) existing.remove()

    const overlay = document.createElement("div")
    overlay.id = "doc-preview-modal"
    overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
    overlay.addEventListener("click", (e) => { if (e.target === overlay) this.closeModal() })

    const box = document.createElement("div")
    box.className = "relative bg-white dark:bg-gray-900 rounded-xl shadow-2xl w-full max-w-4xl overflow-hidden"

    const closeBtn = document.createElement("button")
    closeBtn.className = "absolute top-3 right-3 z-10 text-gray-500 hover:text-gray-900 dark:hover:text-white bg-white dark:bg-gray-800 rounded-full p-1 shadow"
    closeBtn.innerHTML = `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>`
    closeBtn.addEventListener("click", () => this.closeModal())

    const body = document.createElement("div")
    body.className = "p-4"
    body.innerHTML = content

    box.appendChild(closeBtn)
    box.appendChild(body)
    overlay.appendChild(box)
    document.body.appendChild(overlay)

    this._escHandler = (e) => { if (e.key === "Escape") this.closeModal() }
    document.addEventListener("keydown", this._escHandler)
    document.body.style.overflow = "hidden"
  }

  closeModal() {
    const modal = document.getElementById("doc-preview-modal")
    if (modal) modal.remove()
    if (this._escHandler) {
      document.removeEventListener("keydown", this._escHandler)
      this._escHandler = null
    }
    document.body.style.overflow = ""
  }
}
