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

    // A "New Player" has no player_id, so read the slot through the helper
    // rather than off the select - otherwise it looks like an empty slot and
    // gets dropped on the floor during a swap.
    const dragged = (data.isNew || data.playerId === 'new')
      ? { isNew: true }
      : { playerId: data.playerId, playerName: data.playerName }
    const displaced = typeof window.slotOccupant === "function" ? window.slotOccupant(targetIndex) : null

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

    if (typeof window.setSlotOccupant !== "function") return

    // Coming from another slot: whoever was in the target moves back into it,
    // which also vacates the source when the target was empty
    const fromSlot = data.sourceType === "slot" &&
      data.sourceIndex !== undefined &&
      String(data.sourceIndex) !== String(targetIndex)
    if (fromSlot) {
      window.setSlotOccupant(data.sourceIndex, displaced)
    }

    window.setSlotOccupant(targetIndex, dragged)

    // Trigger form submit using the tracked submit function or fallback to direct form
    if (typeof window.submitFormWithTracking === "function") {
      window.submitFormWithTracking()
    } else {
      const form = document.getElementById('lobby-form') || this.element.querySelector("form")
      if (form) form.requestSubmit()
    }

    // Update all lists and prediction immediately
    if (typeof window.updateAverageElos === "function") window.updateAverageElos()
    if (typeof window.updatePrediction === "function") window.updatePrediction()

    setTimeout(() => {
      if (typeof window.renderPlayerResults === "function") window.renderPlayerResults()
      if (typeof window.renderRecentPlayers === "function") window.renderRecentPlayers()
      if (typeof window.renderObservers === "function") window.renderObservers()
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

    // Update prediction after moving player to observers
    if (typeof window.updateAverageElos === "function") window.updateAverageElos()
    if (typeof window.updatePrediction === "function") window.updatePrediction()
  }
}
