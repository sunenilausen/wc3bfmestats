import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  submit() {
    // Use requestSubmit to trigger proper form submission with Turbo
    this.formTarget.requestSubmit()
  }
}
