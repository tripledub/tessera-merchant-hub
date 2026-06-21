import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]
  static values = { url: String }

  update() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      "kyc_document[document_type]": this.selectTarget.value,
      "kyc_document[classification_status]": "confirmed"
    })

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": token,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: body
    })
  }
}
