import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["select"]
  static values = { url: String, status: String }

  // Picking a document type is not the same as confirming it (MH-287) —
  // confirming is what the checkmark button (#confirm) is for. Submitting
  // "confirmed" here meant merely opening the dropdown instantly counted the
  // document as confirmed: for a processing_statement document, that
  // triggered RouteFromKycDocument immediately, which hides this dropdown as
  // a side effect, before the user had any chance to correct a mis-pick.
  change() {
    this.#submit("auto_classified")
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
