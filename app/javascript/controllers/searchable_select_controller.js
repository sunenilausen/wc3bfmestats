import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.createSearchableSelect()
  }

  createSearchableSelect() {
    const select = this.element
    select.style.display = "none"

    // Create wrapper
    this.wrapper = document.createElement("div")
    this.wrapper.className = "searchable-select"
    select.parentNode.insertBefore(this.wrapper, select)

    // Create display/input area
    this.display = document.createElement("div")
    this.display.className = "searchable-select-display"
    this.wrapper.appendChild(this.display)

    // Create search input
    this.input = document.createElement("input")
    this.input.type = "text"
    this.input.className = "searchable-select-input"
    this.input.placeholder = "Search..."
    this.display.appendChild(this.input)

    // Create dropdown
    this.dropdown = document.createElement("div")
    this.dropdown.className = "searchable-select-dropdown"
    this.dropdown.style.display = "none"
    this.wrapper.appendChild(this.dropdown)

    // Store options
    this.options = Array.from(select.options).map(opt => ({
      value: opt.value,
      text: opt.text,
      selected: opt.selected
    }))

    this.isMultiple = select.multiple
    this.renderSelected()
    this.renderOptions()
    this.bindEvents()
  }

  renderSelected() {
    // Clear existing tags (but keep input)
    Array.from(this.display.querySelectorAll(".searchable-select-tag")).forEach(el => el.remove())

    const selected = this.options.filter(o => o.selected && o.value)

    if (this.isMultiple) {
      selected.forEach(opt => {
        const tag = document.createElement("span")
        tag.className = "searchable-select-tag"
        tag.innerHTML = `${opt.text} <span class="searchable-select-tag-remove" data-value="${opt.value}">&times;</span>`
        this.display.insertBefore(tag, this.input)
      })
      this.input.placeholder = selected.length ? "" : "Search..."
    } else {
      if (selected.length) {
        this.input.value = selected[0].text
      }
    }

    // Sync with original select
    this.syncSelect()
  }

  renderOptions(filter = "") {
    this.dropdown.innerHTML = ""
    const filterLower = filter.toLowerCase()

    this.options.forEach(opt => {
      if (!opt.value) return // Skip empty option
      if (filter && !opt.text.toLowerCase().includes(filterLower)) return
      if (this.isMultiple && opt.selected) return // Hide selected in multi

      const div = document.createElement("div")
      div.className = "searchable-select-option" + (opt.selected ? " selected" : "")
      div.textContent = opt.text
      div.dataset.value = opt.value
      this.dropdown.appendChild(div)
    })
  }

  syncSelect() {
    const select = this.element
    Array.from(select.options).forEach(opt => {
      const found = this.options.find(o => o.value === opt.value)
      opt.selected = found ? found.selected : false
    })
    // Trigger both the event and the inline onchange handler
    select.dispatchEvent(new Event("change", { bubbles: true }))
    if (select.onchange) {
      select.onchange()
    }
  }

  bindEvents() {
    this.input.addEventListener("focus", () => this.showDropdown())
    this.input.addEventListener("input", (e) => {
      this.showDropdown()
      this.renderOptions(e.target.value)
    })

    this.dropdown.addEventListener("click", (e) => {
      const option = e.target.closest(".searchable-select-option")
      if (option) {
        this.selectOption(option.dataset.value)
      }
    })

    this.display.addEventListener("click", (e) => {
      const remove = e.target.closest(".searchable-select-tag-remove")
      if (remove) {
        e.stopPropagation()
        this.deselectOption(remove.dataset.value)
      } else {
        this.input.focus()
      }
    })

    document.addEventListener("click", this.handleOutsideClick.bind(this))
  }

  handleOutsideClick(e) {
    if (!this.wrapper.contains(e.target)) {
      this.hideDropdown()
    }
  }

  showDropdown() {
    this.dropdown.style.display = "block"
  }

  hideDropdown() {
    this.dropdown.style.display = "none"
    if (!this.isMultiple) {
      const selected = this.options.find(o => o.selected)
      this.input.value = selected ? selected.text : ""
    } else {
      this.input.value = ""
    }
    this.renderOptions()
  }

  selectOption(value) {
    if (this.isMultiple) {
      const opt = this.options.find(o => o.value === value)
      if (opt) opt.selected = true
      this.input.value = ""
    } else {
      this.options.forEach(o => o.selected = o.value === value)
      this.hideDropdown()
    }
    this.renderSelected()
    this.renderOptions(this.input.value)
  }

  deselectOption(value) {
    const opt = this.options.find(o => o.value === value)
    if (opt) opt.selected = false
    this.renderSelected()
    this.renderOptions(this.input.value)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick.bind(this))
    if (this.wrapper) {
      this.wrapper.remove()
    }
    this.element.style.display = ""
  }
}
