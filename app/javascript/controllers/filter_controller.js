// Submits the containing form when a watched input changes.
// Usage:
//   <form data-controller="filter" data-turbo-action="advance">
//     <select data-action="change->filter#submit">…</select>
//   </form>
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
