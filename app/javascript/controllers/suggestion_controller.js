import { Controller } from "@hotwired/stimulus"

// Powers the "Use suggestion" button on the book edit form.
// Wrap each suggestable field in `data-controller="suggestion"`, mark its
// input with `data-suggestion-target="input"`, and add a button with
// `data-action="suggestion#apply"` and `data-suggestion-proposed-value="..."`.
export default class extends Controller {
  static targets = ["input"]
  static values  = { proposed: String }

  apply(event) {
    event.preventDefault()
    this.inputTarget.value = this.proposedValue
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.inputTarget.focus()
  }
}
