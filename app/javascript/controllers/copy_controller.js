import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { value: String }

  async copy() {
    await navigator.clipboard.writeText(this.valueValue)
    const original = this.element.textContent
    this.element.textContent = "Copied"
    setTimeout(() => { this.element.textContent = original }, 1500)
  }
}
