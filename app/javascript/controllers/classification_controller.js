import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["select"]
  static values = { url: String, status: String }

  change() {
    this.#submit("confirmed")
  }

  confirm() {
    const newStatus = this.statusValue === "confirmed" ? "auto_classified" : "confirmed"
    this.#submit(newStatus)
  }

  #submit(status) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      "kyc_document[document_type]": this.selectTarget.value,
      "kyc_document[classification_status]": status
    })

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": token,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: body
    }).then(response => {
      if (response.ok) return response.text()
    }).then(html => {
      if (html) Turbo.renderStreamMessage(html)
    })
  }
}
