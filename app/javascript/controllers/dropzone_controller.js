import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["input", "list", "submit", "zone"]
  static values  = { url: String }

  connect() {
    this.files = []
  }

  dragover(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("border-brand-400")
  }

  dragleave() {
    this.zoneTarget.classList.remove("border-brand-400")
  }

  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("border-brand-400")
    this.handleFiles(event.dataTransfer.files)
  }

  browse(event) {
    if (event.target === this.inputTarget) return
    this.inputTarget.click()
  }

  pick(event) {
    this.handleFiles(event.target.files)
    event.target.value = ""
  }

  async submit(event) {
    event.preventDefault()
    this.submitTarget.disabled = true
    await Promise.all(this.files.map(f => this.upload(f)))
    this.element.closest("form").submit()
  }

  handleFiles(fileList) {
    Array.from(fileList).forEach(file => {
      this.files.push(file)
      const li = document.createElement("li")
      li.textContent = file.name
      li.className = "text-theme-sm text-gray-700"
      this.listTarget.appendChild(li)
    })
  }

  upload(file) {
    return new Promise((resolve, reject) => {
      const upload = new DirectUpload(file, this.urlValue)
      upload.create((error, blob) => {
        if (error) { reject(error); return }
        const hidden = document.createElement("input")
        hidden.type  = "hidden"
        hidden.name  = "kyc_document[files][]"
        hidden.value = blob.signed_id
        this.element.closest("form").appendChild(hidden)
        resolve()
      })
    })
  }
}
