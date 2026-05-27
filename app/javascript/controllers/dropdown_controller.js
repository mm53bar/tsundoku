import { Controller } from "@hotwired/stimulus"

// Minimal click-to-toggle dropdown. Wraps a trigger button and a `menu`
// target; clicking the trigger toggles the menu, clicking outside or
// pressing Escape closes it. Will be replaced when we do the full Rails
// Blocks navbar refactor — same UX, their richer keyboard nav.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleEscape = this.handleEscape.bind(this)
  }

  disconnect() {
    this.removeGlobalListeners()
  }

  toggle(event) {
    event.stopPropagation()
    if (this.menuTarget.classList.contains("hidden")) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this.handleOutsideClick)
    document.addEventListener("keydown", this.handleEscape)
  }

  hide() {
    this.menuTarget.classList.add("hidden")
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
