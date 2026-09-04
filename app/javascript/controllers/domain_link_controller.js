import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["select"]
  static values = { url: String }

  change() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      "kyc_document[applicant_domain_id]": this.selectTarget.value
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
