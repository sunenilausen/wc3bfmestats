import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="average-elo"
export default class extends Controller {
    static targets = ["option", "playerSelect"]


    connect() {
        // No-op: all updates handled by data-action in the view
    }

    // calculateAverageElo removed: now handled by average-elo controller
}
