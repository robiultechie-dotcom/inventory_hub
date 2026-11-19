import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "selectAll",
    "rowCheckbox",
    "counter",
    "toolbar",
    "singleAction",
    "bulkAction",
    "form",
    "idsContainer",
    "operationInput"
  ]

  connect() {
    this.syncState()
  }

  toggleAll(event) {
    const checked = event.currentTarget.checked
    this.visibleCheckboxes().forEach((cb) => {
      cb.checked = checked
      cb.closest("tr")?.classList.toggle("row-selected", checked)
    })
    this.syncState()
  }

  toggleRow(event) {
    const cb = event.currentTarget
    cb.closest("tr")?.classList.toggle("row-selected", cb.checked)
    this.syncState()
  }

  openSelected() {
    const selected = this.checkedBoxes()
    if (selected.length !== 1) return
    const url = selected[0].closest("tr")?.dataset.url
    if (url) window.location.href = url
  }

  async likeSelected() {
    const selected = this.checkedBoxes()
    if (selected.length === 0) return

    for (const cb of selected) {
      const row = cb.closest("tr")
      const likeUrl = row?.dataset.likeUrl
      if (likeUrl && window.toggleItemLike) {
        await window.toggleItemLike(likeUrl)
      }
    }
  }

  exportCsv(event) {
    const selected = this.checkedBoxes()
    if (selected.length === 0) return
    const baseUrl = event.currentTarget.dataset.exportUrl
    if (!baseUrl) return

    const params = selected.map((cb) => `ids[]=${encodeURIComponent(cb.value)}`).join("&")
    window.location.href = `${baseUrl}?${params}`
  }

  submitBulk(event) {
    const selected = this.checkedBoxes()
    if (selected.length === 0 || !this.hasFormTarget) return

    const confirmMsg = event.currentTarget.dataset.confirmMessage
    if (confirmMsg && !window.confirm(confirmMsg)) return

    this.populateIds(selected)
    this.formTarget.requestSubmit()
  }

  submitOperation(event) {
    const selected = this.checkedBoxes()
    if (selected.length === 0 || !this.hasFormTarget) return

    const confirmMsg = event.currentTarget.dataset.confirmMessage
    if (confirmMsg && !window.confirm(confirmMsg)) return

    const operation = event.currentTarget.dataset.operation
    if (this.hasOperationInputTarget && operation) {
      this.operationInputTarget.value = operation
    }

    this.populateIds(selected)
    this.formTarget.requestSubmit()
  }

  populateIds(selectedBoxes) {
    if (!this.hasIdsContainerTarget) return
    this.idsContainerTarget.innerHTML = ""
    selectedBoxes.forEach((cb) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "ids[]"
      input.value = cb.value
      this.idsContainerTarget.appendChild(input)
    })
  }

  visibleCheckboxes() {
    return this.rowCheckboxTargets.filter((cb) => !cb.closest("tr")?.classList.contains("d-none"))
  }

  checkedBoxes() {
    return this.visibleCheckboxes().filter((cb) => cb.checked)
  }

  syncState() {
    const visible = this.visibleCheckboxes()
    const checked = this.checkedBoxes()
    const count = checked.length

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = visible.length > 0 && count === visible.length
      this.selectAllTarget.indeterminate = count > 0 && count < visible.length
    }

    if (this.hasCounterTarget) {
      const label = this.counterTarget.dataset.label || "selected"
      this.counterTarget.textContent = `${count} ${label}`
      this.counterTarget.className = count > 0
        ? "badge text-bg-primary rounded-pill font-mono px-3 py-1"
        : "badge text-bg-secondary rounded-pill font-mono px-3 py-1"
    }

    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle("active-selection", count > 0)
    }

    this.singleActionTargets.forEach((btn) => {
      btn.disabled = count !== 1
    })

    this.bulkActionTargets.forEach((btn) => {
      btn.disabled = count === 0
    })
  }
}