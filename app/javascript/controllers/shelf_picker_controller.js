import { Controller } from "@hotwired/stimulus"

// Toggles the add-to-shelf panel. The trigger flips the panel between
// hidden and visible; outside click or Escape closes it. Membership
// toggles inside the panel post via Turbo Stream so the panel stays
// open across individual shelf changes.
//
// Two coordination concerns when the panel is rendered per-card on the
// library grid:
//   1. The panel is absolute-positioned and can overflow the viewport
//      when its anchor card is near the edge. show() measures and flips
//      the alignment when needed.
//   2. Opening one card's picker should close any other card's open
//      picker — otherwise multiple panels stack. A custom event is
//      dispatched on show; every other shelf-picker listens and closes.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleEscape       = this.handleEscape.bind(this)
    this.handleOtherOpening = this.handleOtherOpening.bind(this)
    document.addEventListener("shelf-picker:opening", this.handleOtherOpening)
  }

  disconnect() {
    this.removeGlobalListeners()
    document.removeEventListener("shelf-picker:opening", this.handleOtherOpening)
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
    document.dispatchEvent(
      new CustomEvent("shelf-picker:opening", { detail: { source: this } })
    )
    this.panelTarget.classList.remove("hidden")
    this.adjustPosition()
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

  // If another shelf-picker is opening, close this one. The event's
  // detail.source carries the controller that fired it; ignore our own
  // dispatch.
  handleOtherOpening(event) {
    if (event.detail.source === this) return
    if (!this.panelTarget.classList.contains("hidden")) this.hide()
  }

  // Default anchoring is right-aligned to the trigger (Tailwind
  // `right-0`); panel extends leftward. That breaks for trigger
  // positions near the left edge of the viewport. Measure after show
  // and flip to `left-0` (extends rightward) when the panel would
  // overflow the left edge. Same logic in reverse for unusual right-
  // edge overflows.
  adjustPosition() {
    // Reset to the default class state before measuring so a previous
    // flip doesn't carry over to a different card on the same page.
    this.panelTarget.classList.add("right-0")
    this.panelTarget.classList.remove("left-0")

    const rect   = this.panelTarget.getBoundingClientRect()
    const margin = 8

    if (rect.left < margin) {
      this.panelTarget.classList.remove("right-0")
      this.panelTarget.classList.add("left-0")
    } else if (rect.right > window.innerWidth - margin) {
      this.panelTarget.classList.add("right-0")
      this.panelTarget.classList.remove("left-0")
    }
  }

  removeGlobalListeners() {
    document.removeEventListener("click", this.handleOutsideClick)
    document.removeEventListener("keydown", this.handleEscape)
  }
}
