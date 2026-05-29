import { Controller } from "@hotwired/stimulus"

// Debounced autocomplete for the navbar search input. On each keystroke
// we wait `debounce` ms, then load `urlValue?q=<input>` into the dropdown's
// turbo-frame. The server returns a fragment of <turbo-frame id="..."> and
// Turbo swaps it in. Clicking a result navigates _top out of the dropdown.
//
// The dropdown is shown/hidden by toggling `hidden` on the wrapper — Escape
// closes it, as does a click outside the controller element.
export default class extends Controller {
  static targets = ["input", "frame", "dropdown"]
  static values  = {
    url:      String,
    debounce: { type: Number, default: 200 },
    min:      { type: Number, default: 2 }
  }

  connect() {
    this.timeout = null
    this.boundClose = this.closeOnOutside.bind(this)
    document.addEventListener("click", this.boundClose)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
    if (this.timeout) clearTimeout(this.timeout)
  }

  query() {
    clearTimeout(this.timeout)
    const q = this.inputTarget.value.trim()

    if (q.length < this.minValue) {
      this.hide()
      return
    }

    this.timeout = setTimeout(() => {
      this.frameTarget.src = `${this.urlValue}?q=${encodeURIComponent(q)}`
      this.show()
    }, this.debounceValue)
  }

  focus() {
    if (this.inputTarget.value.trim().length >= this.minValue) {
      this.show()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.inputTarget.value = ""
      this.hide()
      this.inputTarget.blur()
    }
  }

  show() {
    this.dropdownTarget.hidden = false
  }

  hide() {
    this.dropdownTarget.hidden = true
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }
}
