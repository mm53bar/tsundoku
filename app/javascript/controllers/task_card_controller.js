import { Controller } from "@hotwired/stimulus"

// Auto-dismisses succeeded task cards from the active-tasks banner so the
// strip doesn't accumulate stale entries. Failed cards persist until the
// user navigates away or a fresh broadcast prunes them server-side.
export default class extends Controller {
  static values = {
    status: String,
    autoDismissMs: { type: Number, default: 30000 },
    fadeMs: { type: Number, default: 500 }
  }

  connect() {
    if (this.statusValue === "succeeded") {
      this.timeout = setTimeout(() => this.dismiss(), this.autoDismissMsValue)
    }
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("opacity-0")
    setTimeout(() => this.element.remove(), this.fadeMsValue)
  }
}
