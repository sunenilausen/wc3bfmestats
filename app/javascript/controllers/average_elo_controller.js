import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="average-elo"
export default class extends Controller {
    static targets = ["value"];

    connect() {
        this.listenForSelectChanges();
        this.calculateAverageElo();
    }

    listenForSelectChanges() {
        const teamNumber = this.element.getAttribute('data-team');
        const selects = document.querySelectorAll(`tr.nested-fields[data-team="${teamNumber}"] select[data-average-elo-target="playerSelect"]`);
        selects.forEach(select => {
            select.addEventListener('change', () => this.calculateAverageElo());
        });
    }

    calculateAverageElo() {
        const teamNumber = this.element.getAttribute('data-team');
        const selects = document.querySelectorAll(`tr.nested-fields[data-team="${teamNumber}"] select[data-average-elo-target="playerSelect"]`);
        let totalElo = 0;
        let count = 0;
        selects.forEach(select => {
            const selectedOption = select.options[select.selectedIndex];
            if (selectedOption && selectedOption.dataset.elo) {
                const elo = parseInt(selectedOption.dataset.elo, 10);
                if (!isNaN(elo)) {
                    totalElo += elo;
                    count++;
                }
            }
        });
        const averageElo = count > 0 ? Math.round(totalElo / count) : 0;
        if (this.hasValueTarget) {
            this.valueTarget.textContent = averageElo;
        }
    }
}
