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
    setTimeout(() => {
      this.element.remove()
      this.collapseBannerIfEmpty()
    }, this.fadeMsValue)
  }

  // Once a card is gone, check the active-tasks container. If no cards
  // remain, clear the banner chrome (the amber wrapper, padding) so we
  // don't leave a hollow stripe behind. The server-side `_active_list`
  // partial does the same gating on initial render; this is the client
  // equivalent after Stimulus removes the last card.
  collapseBannerIfEmpty() {
    const container = document.getElementById("active_tasks")
    if (!container) return
    const remaining = container.querySelectorAll('[data-controller~="task-card"]')
    if (remaining.length === 0) {
      container.innerHTML = ""
    }
  }
}
