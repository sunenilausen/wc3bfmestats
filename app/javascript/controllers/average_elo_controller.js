import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="average-elo"
export default class extends Controller {
    static targets = ["value", "glickoValue", "glickoRd"];

    connect() {
        // Only run in edit mode where there are player selects
        const selects = this.element.querySelectorAll('select[data-average-elo-target="playerSelect"]');
        if (selects.length > 0) {
            this.listenForSelectChanges();
            this.calculateAverages();
        }
    }

    listenForSelectChanges() {
        const teamNumber = this.element.getAttribute('data-team');
        const selects = document.querySelectorAll(`tr.nested-fields[data-team="${teamNumber}"] select[data-average-elo-target="playerSelect"]`);
        selects.forEach(select => {
            select.addEventListener('change', () => this.calculateAverages());
        });
    }

    calculateAverageElo() {
        this.calculateAverages();
    }

    calculateAverages() {
        const teamNumber = this.element.getAttribute('data-team');
        const selects = document.querySelectorAll(`tr.nested-fields[data-team="${teamNumber}"] select[data-average-elo-target="playerSelect"]`);

        let totalElo = 0;
        let totalGlicko = 0;
        let rdSquaredSum = 0;
        let count = 0;

        selects.forEach(select => {
            const selectedOption = select.options[select.selectedIndex];
            if (selectedOption && selectedOption.dataset.elo) {
                const elo = parseInt(selectedOption.dataset.elo, 10);
                const glicko = parseInt(selectedOption.dataset.glicko, 10) || 1500;
                const rd = parseInt(selectedOption.dataset.glickoRd, 10) || 350;

                if (!isNaN(elo)) {
                    totalElo += elo;
                    totalGlicko += glicko;
                    rdSquaredSum += rd * rd;
                    count++;
                }
            }
        });

        const averageElo = count > 0 ? Math.round(totalElo / count) : 0;
        const averageGlicko = count > 0 ? Math.round(totalGlicko / count) : 0;
        const pooledRd = count > 0 ? Math.round(Math.sqrt(rdSquaredSum / count)) : 350;

        if (this.hasValueTarget) {
            this.valueTarget.textContent = averageElo;
        }
        if (this.hasGlickoValueTarget) {
            this.glickoValueTarget.textContent = averageGlicko;
        }
        if (this.hasGlickoRdTarget) {
            this.glickoRdTarget.textContent = pooledRd;
        }
    }
}
