import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["input", "list", "submit", "zone"]
  static values  = { url: String, folderMessage: String }

  connect() {
    this.files = []
    this.onSubmitEnd = this.reset.bind(this)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  dragover(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("border-brand-400")
  }

  dragleave() {
    this.zoneTarget.classList.remove("border-brand-400")
  }

  // Plain dataTransfer.files only surfaces top-level entries — a dropped
  // folder shows up as an empty/invalid File-like entry, its contents are
  // never recursed into, and it silently fails server-side validation with
  // no feedback (MH-275). dataTransfer.items + webkitGetAsEntry() lets us
  // detect and skip directories before they ever reach upload().
  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("border-brand-400")

    const items = event.dataTransfer.items
    if (!items || !items.length) {
      this.handleFiles(event.dataTransfer.files)
      return
    }

    const files = []
    let droppedFolder = false

    Array.from(items).forEach(item => {
      const entry = item.webkitGetAsEntry && item.webkitGetAsEntry()
      if (entry && entry.isDirectory) {
        droppedFolder = true
        return
      }
      const file = item.getAsFile && item.getAsFile()
      if (file) files.push(file)
    })

    if (droppedFolder) this.showFolderWarning()
    this.handleFiles(files)
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
    this.element.requestSubmit()
  }

  // Turbo renders the response in place instead of reloading the page, so
  // nothing else clears the picked files, the hidden blob inputs from
  // upload(), or the disabled submit button between attempts — without
  // this, a second upload would silently resubmit the first file's blob
  // alongside the new one (duplicate documents) and the button would stay
  // disabled forever.
  reset() {
    this.files = []
    this.listTarget.innerHTML = ""
    this.inputTarget.value = ""
    this.element.querySelectorAll('input[name="kyc_document[files][]"]').forEach(el => el.remove())
    this.submitTarget.disabled = false
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

  // Mirrors shared/_toast.html.erb's warning styling so this reads as the
  // same toast system, without a server round-trip for a client-only check.
  showFolderWarning() {
    const toast = document.createElement("div")
    toast.dataset.controller = "toast"
    toast.className = "flex w-full max-w-sm items-center justify-between gap-3 rounded-md border-b-4 border-warning-500 bg-white p-3 shadow-lg transition-all duration-300 translate-x-full opacity-0 dark:bg-[#1E2634]"

    const message = document.createElement("p")
    message.className = "text-sm font-medium text-gray-800 dark:text-white/90"
    message.textContent = this.folderMessageValue

    const dismiss = document.createElement("button")
    dismiss.dataset.action = "click->toast#dismiss"
    dismiss.className = "flex-shrink-0 text-gray-400 hover:text-gray-800 dark:hover:text-white/90"
    dismiss.textContent = "×"

    toast.append(message, dismiss)
    document.getElementById("toast-container").appendChild(toast)
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
