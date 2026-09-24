import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["select", "confirmButton"]
  static values = { url: String, status: String }

  connect() {
    this.#syncConfirmAvailability()
  }

  // Picking a document type is not the same as confirming it (MH-287) —
  // confirming is what the checkmark button (#confirm) is for. Submitting
  // "confirmed" here meant merely opening the dropdown instantly counted the
  // document as confirmed: for a processing_statement document, that
  // triggered RouteFromKycDocument immediately, which hides this dropdown as
  // a side effect, before the user had any chance to correct a mis-pick.
  change() {
    this.#submit("auto_classified")
    this.#syncConfirmAvailability()
  }

  // MH-332: without a real type selected, this.selectTarget.value is the
  // disabled placeholder option's empty string — submitting that leaves the
  // document confirmed but permanently "Unclassified", since the server
  // silently drops a blank document_type rather than rejecting the whole
  // update. The button is already disabled in that state (see the ERB and
  // #syncConfirmAvailability), but this guard covers it regardless of how
  // the click was triggered.
  confirm() {
    const newStatus = this.statusValue === "confirmed" ? "auto_classified" : "confirmed"
    if (newStatus === "confirmed" && !this.selectTarget.value) return

    this.#submit(newStatus)
  }

  #syncConfirmAvailability() {
    if (!this.hasConfirmButtonTarget) return

    this.confirmButtonTarget.disabled = !this.selectTarget.value
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
