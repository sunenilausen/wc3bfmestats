import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="average-cr"
export default class extends Controller {
    static targets = ["value"];

    connect() {
        // Only run in edit mode where there are player selects
        const selects = this.element.querySelectorAll('select[data-average-cr-target="playerSelect"]');
        if (selects.length > 0) {
            this.listenForSelectChanges();
            this.calculateAverages();
        }
    }

    listenForSelectChanges() {
        const teamNumber = this.element.getAttribute('data-team');
        const selects = document.querySelectorAll(`tr.nested-fields[data-team="${teamNumber}"] select[data-average-cr-target="playerSelect"]`);
        selects.forEach(select => {
            select.addEventListener('change', () => this.calculateAverages());
        });
    }

    calculateAverageCr() {
        this.calculateAverages();
    }

    calculateAverages() {
        const teamNumber = this.element.getAttribute('data-team');
        const selects = document.querySelectorAll(`tr.nested-fields[data-team="${teamNumber}"] select[data-average-cr-target="playerSelect"]`);

        let totalCr = 0;
        let count = 0;

        selects.forEach(select => {
            const selectedOption = select.options[select.selectedIndex];
            if (selectedOption && selectedOption.dataset.cr) {
                const cr = parseInt(selectedOption.dataset.cr, 10);

                if (!isNaN(cr)) {
                    totalCr += cr;
                    count++;
                }
            }
        });

        const averageCr = count > 0 ? Math.round(totalCr / count) : 0;

        if (this.hasValueTarget) {
            this.valueTarget.textContent = averageCr;
        }
    }
}
