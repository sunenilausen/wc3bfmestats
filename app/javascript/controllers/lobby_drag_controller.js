import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["playerSlot", "observerZone"]

  connect() {
    this.setupDropZones()
  }

  setupDropZones() {
    // Setup drop zones on player slots
    this.playerSlotTargets.forEach(slot => {
      slot.addEventListener("dragover", this.handleDragOver.bind(this))
      slot.addEventListener("dragleave", this.handleDragLeave.bind(this))
      slot.addEventListener("drop", this.handleDrop.bind(this))
    })

    // Setup observer drop zone
    if (this.hasObserverZoneTarget) {
      this.observerZoneTarget.addEventListener("dragover", this.handleDragOver.bind(this))
      this.observerZoneTarget.addEventListener("dragleave", this.handleDragLeave.bind(this))
      this.observerZoneTarget.addEventListener("drop", this.handleDropObserver.bind(this))
    }
  }

  handleDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
    e.currentTarget.classList.add("drop-zone-hover")
  }

  handleDragLeave(e) {
    e.currentTarget.classList.remove("drop-zone-hover")
  }

  handleDrop(e) {
    e.preventDefault()
    e.currentTarget.classList.remove("drop-zone-hover")

    const data = JSON.parse(e.dataTransfer.getData("text/plain"))
    const targetSlot = e.currentTarget
    const targetIndex = targetSlot.dataset.slotIndex
    const targetSelect = document.getElementById('player-select-' + targetIndex)

    if (!targetSelect) return

    // Get existing player in target slot for potential swap
    const existingPlayerId = targetSelect.value
    const existingPlayerName = targetSelect.options[targetSelect.selectedIndex]?.text

    // If dragging from observer, remove from observers first
    if (data.sourceType === "observer") {
      const observerSelect = document.getElementById('observer-select')
      if (observerSelect) {
        const option = observerSelect.querySelector(`option[value="${data.playerId}"]`)
        if (option && option.selected) {
          option.selected = false
        }
      }
    }

    // If dragging from another slot, handle swap
    if (data.sourceType === "slot" && data.sourceIndex !== undefined && String(data.sourceIndex) !== String(targetIndex)) {
      const sourceSelect = document.getElementById('player-select-' + data.sourceIndex)
      if (sourceSelect) {
        // Set source slot to existing target player (swap)
        sourceSelect.value = existingPlayerId || ''
        sourceSelect.dispatchEvent(new Event('change', { bubbles: true }))

        // Update source slot display
        if (typeof window.updateSlotDisplay === "function") {
          if (existingPlayerId && existingPlayerName) {
            window.updateSlotDisplay(data.sourceIndex, existingPlayerId, existingPlayerName)
          } else {
            window.updateSlotDisplay(data.sourceIndex, null, null)
          }
        }
      }
    }

    // Set target slot to dragged player
    targetSelect.value = data.playerId
    targetSelect.dispatchEvent(new Event('change', { bubbles: true }))

    // Update target slot display
    if (typeof window.updateSlotDisplay === "function") {
      window.updateSlotDisplay(targetIndex, data.playerId, data.playerName)
    }

    // Trigger form submit
    const form = this.element.querySelector("form")
    if (form) form.requestSubmit()

    // Update all lists
    setTimeout(() => {
      if (typeof window.renderPlayerResults === "function") window.renderPlayerResults()
      if (typeof window.renderRecentPlayers === "function") window.renderRecentPlayers()
      if (typeof window.renderObservers === "function") window.renderObservers()
      if (typeof window.updateAverageElos === "function") window.updateAverageElos()
      if (typeof window.updatePrediction === "function") window.updatePrediction()
    }, 100)
  }

  handleDropObserver(e) {
    e.preventDefault()
    e.currentTarget.classList.remove("drop-zone-hover")

    const data = JSON.parse(e.dataTransfer.getData("text/plain"))

    // If dragging from a slot, clear that slot first
    if (data.sourceType === "slot" && data.sourceIndex !== undefined) {
      const sourceSelect = document.getElementById('player-select-' + data.sourceIndex)
      if (sourceSelect) {
        sourceSelect.value = ''
        sourceSelect.dispatchEvent(new Event('change', { bubbles: true }))

        if (typeof window.updateSlotDisplay === "function") {
          window.updateSlotDisplay(data.sourceIndex, null, null)
        }
      }
    }

    if (typeof window.addObserver === "function") {
      window.addObserver(data.playerId)
    }
  }
}
