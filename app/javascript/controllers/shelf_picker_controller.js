import { Controller } from "@hotwired/stimulus"

// Toggles the add-to-shelf panel on the book detail page.
// Clicking the trigger flips the panel between hidden and visible;
// clicking outside or pressing Escape closes it. Membership toggles
// inside the panel are handled by Turbo Stream form submissions, so
// the panel stays open across individual shelf changes — the user
// can check multiple boxes without re-opening.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleEscape = this.handleEscape.bind(this)
  }

  disconnect() {
    this.removeGlobalListeners()
  }

  toggle(event) {
    event.stopPropagation()
    if (this.panelTarget.classList.contains("hidden")) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.panelTarget.classList.remove("hidden")
    document.addEventListener("click", this.handleOutsideClick)
    document.addEventListener("keydown", this.handleEscape)
  }

  hide() {
    this.panelTarget.classList.add("hidden")
    this.removeGlobalListeners()
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  handleEscape(event) {
    if (event.key === "Escape") this.hide()
  }

  removeGlobalListeners() {
    document.removeEventListener("click", this.handleOutsideClick)
    document.removeEventListener("keydown", this.handleEscape)
  }
}
