import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["input", "list", "submit", "zone"]
  static values  = { url: String }

  connect() {
    this.files = []
    console.log("[dropzone] connected", this.element)
    console.log("[dropzone] zoneTarget", this.zoneTarget)
    console.log("[dropzone] inputTarget", this.inputTarget)
  }

  dragover(event) {
    console.log("[dropzone] dragover")
    event.preventDefault()
    this.zoneTarget.classList.add("border-brand-400")
  }

  dragleave() {
    console.log("[dropzone] dragleave")
    this.zoneTarget.classList.remove("border-brand-400")
  }

  drop(event) {
    console.log("[dropzone] drop", event.dataTransfer.files)
    event.preventDefault()
    this.zoneTarget.classList.remove("border-brand-400")
    this.handleFiles(event.dataTransfer.files)
  }

  browse(event) {
    console.log("[dropzone] browse, target:", event.target, "input:", this.inputTarget)
    if (event.target === this.inputTarget) return
    this.inputTarget.click()
  }

  pick(event) {
    console.log("[dropzone] pick", event.target.files)
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
