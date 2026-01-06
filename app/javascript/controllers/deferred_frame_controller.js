import { Controller } from "@hotwired/stimulus"

// Defers loading of a Turbo Frame until after the page has fully rendered
// Usage: data-controller="deferred-frame" data-deferred-frame-url-value="/path/to/load"
export default class extends Controller {
  static values = { url: String, delay: { type: Number, default: 100 } }

  connect() {
    // Wait for page to be fully rendered, then load the frame
    requestAnimationFrame(() => {
      setTimeout(() => {
        this.element.src = this.urlValue
      }, this.delayValue)
    })
  }
}
