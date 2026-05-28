import { Controller } from "@hotwired/stimulus"

// Client-side typeahead filter for the library grid. Each card carries a
// `data-searchable` attribute containing its title + author names + series
// name (lowercased, space-joined). On input we hide cards whose searchable
// text doesn't include every typed token — multi-word queries narrow
// progressively ("for" then "for ac" still matches "Accelerate Forsgren").
//
// Pure DOM filtering, no server round-trip. With 300+ books and DOM
// already rendered, this stays instant even on a NAS.
export default class extends Controller {
  static targets = ["input", "card", "empty", "count"]

  connect() {
    this.totalCount = this.cardTargets.length
    this.applyFilter()
  }

  filter() {
    this.applyFilter()
  }

  clear(event) {
    event?.preventDefault()
    this.inputTarget.value = ""
    this.applyFilter()
    this.inputTarget.focus()
  }

  applyFilter() {
    const tokens = this.inputTarget.value
      .toLowerCase()
      .split(/\s+/)
      .filter((t) => t.length > 0)

    let visible = 0
    this.cardTargets.forEach((card) => {
      const haystack = card.dataset.searchable || ""
      const match = tokens.every((tok) => haystack.includes(tok))
      card.hidden = !match
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible !== 0 || tokens.length === 0
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent =
        tokens.length === 0
          ? `${this.totalCount}`
          : `${visible} of ${this.totalCount}`
    }
  }
}
