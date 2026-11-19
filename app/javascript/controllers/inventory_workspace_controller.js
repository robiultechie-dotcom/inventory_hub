import { Controller } from "@hotwired/stimulus"

const DEFAULT_SPECS_BY_TYPE = {
  fixed: "📦-",
  random_20bit: "X5_",
  random_32bit: "X8_",
  random_6digit: "D6_",
  random_9digit: "D9_",
  guid: "",
  datetime: "yyyy",
  sequence: "D3"
}

const I18N_WORKSPACE = {
  en: {
    unsaved: "Unsaved changes...",
    saving: "Saving...",
    saved: "All changes saved",
    saveFailed: "Save failed",
    conflict: "Version Conflict!",
    maxElements: "Maximum 10 elements allowed.",
    maxFields: "Maximum of 3 fields for this type already enabled.",
    hints: {
      fixed: "A piece of unchanging text. E.g., you can use Unicode emoji.",
      random_20bit: "A random value. E.g., format it as a six-digit decimal (D6) or 5-digit hex (X5_).",
      random_32bit: "A 32-bit random value. E.g., format it as 8-digit hex (X8) or 10-digit decimal (D10).",
      random_6digit: "A 6-digit random number. Format with leading zeros (D6).",
      random_9digit: "A 9-digit random number. Format with leading zeros (D9).",
      guid: "A globally unique 128-bit UUID.",
      datetime: "An item creation date and time. E.g., use yyyy, MM, dd, ddd, HH, mm, ss.",
      sequence: "A sequential index. E.g., format it with leading zeros (D4) or without them (D)."
    }
  },
  es: {
    unsaved: "Cambios sin guardar...",
    saving: "Guardando...",
    saved: "Todos los cambios guardados",
    saveFailed: "Error al guardar",
    conflict: "¡Conflicto de versión!",
    maxElements: "Se permiten máximo 10 elementos.",
    maxFields: "Ya se habilitaron los 3 campos máximos de este tipo.",
    hints: {
      fixed: "Texto fijo inmutable. P. ej., puedes usar emojis Unicode.",
      random_20bit: "Valor aleatorio de 20 bits. Formatea como decimal (D6) o hex (X5_).",
      random_32bit: "Valor aleatorio de 32 bits. Formatea como hex (X8) o decimal (D10).",
      random_6digit: "Número aleatorio de 6 dígitos con ceros iniciales (D6).",
      random_9digit: "Número aleatorio de 9 dígitos con ceros iniciales (D9).",
      guid: "Identificador único global UUID de 128 bits.",
      datetime: "Fecha y hora de creación. P. ej., usa yyyy, MM, dd, ddd, HH, mm, ss.",
      sequence: "Índice secuencial. Formatea con ceros iniciales (D4) o sin ellos (D)."
    }
  }
}

export default class extends Controller {
  static targets = [
    "headerImage",
    "headerIcon",
    "itemsTableBody",
    "itemFilterInput",
    "itemSortSelect",
    "discussionList",
    "commentForm",
    "commentInput",
    "autoSaveForm",
    "lockVersion",
    "forceOverwriteInput",
    "conflictBanner",
    "conflictMessage",
    "tagInput",
    "markdownInput",
    "dropzone",
    "imageUrlInput",
    "imagePreviewCard",
    "imagePreviewImg",
    "removeImgBtn",
    "idList",
    "idPreview",
    "clearAllInput",
    "fieldsList",
    "fieldTypeSelect",
    "userAccessSelect"
  ]

  get dict() {
    return I18N_WORKSPACE[document.documentElement.lang === "es" ? "es" : "en"]
  }

  connect() {
    this.changeCounter = 0
    this.lastSavedCounter = 0
    this.activeSavePromise = null
    this.popoverInstances = []

    this.beforeUnloadHandler = (event) => {
      if (this.changeCounter > this.lastSavedCounter || this.activeSavePromise) {
        event.preventDefault()
        event.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this.beforeUnloadHandler)

    this.initDiscussionPolling()
    this.initUnifiedAutoSave()
    this.initTagAutocomplete()
    this.initReadyMadeMarkdownEditor()
    this.initReadyMadeDropzone()
    this.initCustomIdBuilder()
    this.initCustomFieldsBuilder()
    this.initUserAccessAutocomplete()
  }

  disconnect() {
    if (this.beforeUnloadHandler) {
      window.removeEventListener("beforeunload", this.beforeUnloadHandler)
    }
    if (this.pollTimer) clearInterval(this.pollTimer)
    if (this.saveTimer) clearInterval(this.saveTimer)

    if (this.tagTomSelect) {
      this.tagTomSelect.destroy()
      this.tagTomSelect = null
    }
    if (this.userTomSelect) {
      this.userTomSelect.destroy()
      this.userTomSelect = null
    }
    if (this.mdeInstance) {
      try { this.mdeInstance.toTextArea() } catch (_) {}
      this.mdeInstance = null
      if (this.hasMarkdownInputTarget) delete this.markdownInputTarget.dataset.mdeInitialized
    }
    if (this.dropzoneInstance) {
      this.dropzoneInstance.destroy()
      this.dropzoneInstance = null
    }
    if (this.idSortable) {
      this.idSortable.destroy()
      this.idSortable = null
    }
    if (this.fieldsSortable) {
      this.fieldsSortable.destroy()
      this.fieldsSortable = null
    }
    if (this.popoverInstances?.length) {
      this.popoverInstances.forEach((p) => p.dispose())
      this.popoverInstances = []
    }
  }

  async flushBeforeTabChange(event) {
    if (!this.hasAutoSaveFormTarget) return
    if (!this.activeSavePromise && this.changeCounter <= this.lastSavedCounter) return

    event.preventDefault()
    const targetUrl = event.currentTarget.href
    let saved = await this.performAutoSave()
    if (saved && this.changeCounter > this.lastSavedCounter) {
      saved = await this.performAutoSave()
    }
    if (saved) {
      window.location.href = targetUrl
    }
  }

  filterAndSortItems() {
    if (!this.hasItemsTableBodyTarget) return
    const query = this.hasItemFilterInputTarget ? this.itemFilterInputTarget.value.trim().toLowerCase() : ""
    const sortMode = this.hasItemSortSelectTarget ? this.itemSortSelectTarget.value : "newest"
    const rows = Array.from(this.itemsTableBodyTarget.querySelectorAll("tr[data-item-row='true']"))

    rows.forEach((row) => {
      const searchable = row.dataset.searchText || row.textContent.toLowerCase()
      const matches = !query || searchable.includes(query)
      row.classList.toggle("d-none", !matches)
    })

    rows.sort((a, b) => {
      if (sortMode === "oldest") return Number(a.dataset.created) - Number(b.dataset.created)
      if (sortMode === "id_asc") return (a.dataset.customId || "").localeCompare(b.dataset.customId || "")
      if (sortMode === "id_desc") return (b.dataset.customId || "").localeCompare(a.dataset.customId || "")
      if (sortMode === "likes_desc") return Number(b.dataset.likes) - Number(a.dataset.likes)
      return Number(b.dataset.created) - Number(a.dataset.created)
    })

    rows.forEach((row) => this.itemsTableBodyTarget.appendChild(row))
  }

  initDiscussionPolling() {
    if (!this.hasDiscussionListTarget) return
    const url = this.discussionListTarget.dataset.pollUrl

    this.pollTimer = setInterval(async () => {
      try {
        const res = await fetch(url, { headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" } })
        if (res.status === 200) {
          const html = await res.text()
          if (this.discussionListTarget.innerHTML.trim() !== html.trim()) {
            this.discussionListTarget.innerHTML = html
          }
        }
      } catch (_) {}
    }, 3000)
  }

  async submitComment(event) {
    event.preventDefault()
    if (!this.hasCommentFormTarget || !this.hasCommentInputTarget) return
    const body = this.commentInputTarget.value.trim()
    if (!body) return

    const formData = new FormData(this.commentFormTarget)
    try {
      const res = await fetch(this.commentFormTarget.action, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "X-Requested-With": "XMLHttpRequest"
        },
        body: formData
      })
      if (res.ok) {
        const html = await res.text()
        if (this.hasDiscussionListTarget) this.discussionListTarget.innerHTML = html
        this.commentInputTarget.value = ""
      }
    } catch (_) {}
  }

  initUnifiedAutoSave() {
    if (!this.hasAutoSaveFormTarget) return

    this.autoSaveFormTarget.addEventListener("input", () => this.markDirty())
    this.autoSaveFormTarget.addEventListener("change", () => this.markDirty())
    this.autoSaveFormTarget.addEventListener("submit", (e) => {
      e.preventDefault()
      this.changeCounter += 1
      this.performAutoSave()
    })

    this.saveTimer = setInterval(() => {
      if (this.changeCounter > this.lastSavedCounter) {
        this.performAutoSave()
      }
    }, 8000)
  }

  markDirty() {
    this.changeCounter += 1
    const headerBadge = document.getElementById("autoSaveBadge")
    if (headerBadge) {
      headerBadge.className = "badge bg-warning-subtle text-warning border border-warning-subtle rounded-pill px-3 py-1 font-mono"
      headerBadge.innerHTML = `<i class="bi bi-arrow-repeat me-1"></i>${this.dict.unsaved}`
    }
  }

  reloadWorkspace() {
    this.lastSavedCounter = this.changeCounter
    window.location.reload()
  }

  async forceOverwrite() {
    if (this.hasForceOverwriteInputTarget) this.forceOverwriteInputTarget.value = "1"
    if (this.hasConflictBannerTarget) this.conflictBannerTarget.classList.add("d-none")
    this.changeCounter += 1
    await this.performAutoSave()
    if (this.hasForceOverwriteInputTarget) this.forceOverwriteInputTarget.value = "0"
  }

  async performAutoSave() {
    if (!this.hasAutoSaveFormTarget) return true
    if (this.activeSavePromise) return await this.activeSavePromise
    if (this.changeCounter <= this.lastSavedCounter) return true

    this.activeSavePromise = this.executeAutoSaveRequest()
    try {
      return await this.activeSavePromise
    } finally {
      this.activeSavePromise = null
    }
  }

  async executeAutoSaveRequest() {
    const snapshotCounter = this.changeCounter
    const headerBadge = document.getElementById("autoSaveBadge")
    if (headerBadge) {
      headerBadge.className = "badge bg-info-subtle text-info border border-info-subtle rounded-pill px-3 py-1 font-mono"
      headerBadge.innerHTML = `<i class="bi bi-cloud-arrow-up me-1"></i>${this.dict.saving}`
    }

    const formData = new FormData(this.autoSaveFormTarget)
    try {
      const res = await fetch(this.autoSaveFormTarget.action, {
        method: "PATCH",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: formData
      })
      const data = await res.json().catch(() => ({}))

      if (res.ok && data.status === "saved") {
        this.lastSavedCounter = Math.max(this.lastSavedCounter, snapshotCounter)
        this.lockVersionTargets.forEach((input) => { input.value = data.lock_version })
        const headerVer = document.getElementById("headerLockVersion")
        if (headerVer) headerVer.textContent = data.lock_version

        if (this.hasIdListTarget && data.next_seq) {
          this.idListTarget.dataset.nextSeq = data.next_seq
        }
        if (this.hasIdPreviewTarget && data.id_preview) {
          this.idPreviewTarget.textContent = data.id_preview
        }
        if (this.hasConflictBannerTarget) this.conflictBannerTarget.classList.add("d-none")

        if (headerBadge) {
          if (this.changeCounter > this.lastSavedCounter) {
            headerBadge.className = "badge bg-warning-subtle text-warning border border-warning-subtle rounded-pill px-3 py-1 font-mono"
            headerBadge.innerHTML = `<i class="bi bi-arrow-repeat me-1"></i>${this.dict.unsaved}`
          } else {
            headerBadge.className = "badge bg-success-subtle text-success border border-success-subtle rounded-pill px-3 py-1"
            headerBadge.innerHTML = `<i class="bi bi-cloud-check-fill me-1"></i>${this.dict.saved} (${data.saved_at})`
          }
        }
        return true
      }

      if (res.status === 409) {
        if (this.hasConflictBannerTarget) {
          this.conflictMessageTarget.textContent = data.message || this.dict.conflict
          this.conflictBannerTarget.classList.remove("d-none")
        }
        if (headerBadge) {
          headerBadge.className = "badge text-bg-danger rounded-pill px-3 py-1"
          headerBadge.textContent = this.dict.conflict
        }
      } else if (headerBadge) {
        headerBadge.className = "badge bg-danger-subtle text-danger border border-danger-subtle rounded-pill px-3 py-1"
        headerBadge.innerHTML = `<i class="bi bi-exclamation-circle me-1"></i>${data.message || this.dict.saveFailed}`
      }
      return false
    } catch (_) {
      if (headerBadge) {
        headerBadge.className = "badge bg-danger-subtle text-danger border border-danger-subtle rounded-pill px-3 py-1"
        headerBadge.innerHTML = `<i class="bi bi-wifi-off me-1"></i>${this.dict.saveFailed}`
      }
      return false
    }
  }

  initTagAutocomplete() {
    if (!this.hasTagInputTarget || !window.TomSelect || this.tagInputTarget.tomselect) return
    const existing = this.tagInputTarget.value.split(",").map((t) => t.trim()).filter(Boolean)
    this.tagTomSelect = new window.TomSelect(this.tagInputTarget, {
      plugins: ["remove_button"],
      persist: false,
      create: true,
      valueField: "name",
      labelField: "name",
      searchField: "name",
      options: existing.map((name) => ({ name })),
      load: (query, callback) => {
        fetch(`/tags/autocomplete?q=${encodeURIComponent(query)}`)
          .then((r) => r.json())
          .then((names) => callback(names.map((name) => ({ name }))))
          .catch(() => callback())
      },
      onChange: () => this.markDirty()
    })
  }

  initReadyMadeMarkdownEditor() {
    if (!this.hasMarkdownInputTarget || !window.EasyMDE || this.markdownInputTarget.dataset.mdeInitialized) return
    this.markdownInputTarget.dataset.mdeInitialized = "true"
    this.mdeInstance = new window.EasyMDE({
      element: this.markdownInputTarget,
      spellChecker: false,
      status: false,
      minHeight: "110px",
      toolbar: ["bold", "italic", "heading", "|", "code", "quote", "unordered-list", "ordered-list", "|", "link", "preview"]
    })
    this.mdeInstance.codemirror.on("change", () => {
      this.markdownInputTarget.value = this.mdeInstance.value()
      this.markDirty()
    })
  }

  initReadyMadeDropzone() {
    if (!this.hasDropzoneTarget || !window.mountCloudDropzone) return

    this.dropzoneInstance = window.mountCloudDropzone(this.dropzoneTarget, {
      hiddenInput: this.hasImageUrlInputTarget ? this.imageUrlInputTarget : null,
      previewCard: this.hasImagePreviewCardTarget ? this.imagePreviewCardTarget : null,
      previewImg: this.hasImagePreviewImgTarget ? this.imagePreviewImgTarget : null,
      removeBtn: this.hasRemoveImgBtnTarget ? this.removeImgBtnTarget : null,
      onUploaded: (url) => {
        if (this.hasHeaderImageTarget) {
          this.headerImageTarget.src = url
          this.headerImageTarget.classList.remove("d-none")
        }
        if (this.hasHeaderIconTarget) this.headerIconTarget.classList.add("d-none")
        this.markDirty()
        this.performAutoSave()
      },
      onRemoved: () => {
        if (this.hasHeaderImageTarget) {
          this.headerImageTarget.src = ""
          this.headerImageTarget.classList.add("d-none")
        }
        if (this.hasHeaderIconTarget) this.headerIconTarget.classList.remove("d-none")
        this.markDirty()
        this.performAutoSave()
      }
    })
  }

  initCustomIdBuilder() {
    if (!this.hasIdListTarget) return
    this.initPopovers()
    this.computeIdPreview()

    if (window.Sortable) {
      let pointerOutside = false
      const trackPointer = (e) => {
        const rect = this.idListTarget.getBoundingClientRect()
        const touch = e.touches?.[0] || e.changedTouches?.[0]
        const clientX = e.clientX ?? touch?.clientX ?? 0
        const clientY = e.clientY ?? touch?.clientY ?? 0
        if (clientX === 0 && clientY === 0) return

        pointerOutside = (
          clientX < rect.left - 25 ||
          clientX > rect.right + 25 ||
          clientY < rect.top - 25 ||
          clientY > rect.bottom + 25
        )
        this.idListTarget.classList.toggle("id-list-drag-outside", pointerOutside)
      }

      this.idSortable = new window.Sortable(this.idListTarget, {
        handle: ".drag-handle",
        animation: 150,
        onStart: () => {
          pointerOutside = false
          document.addEventListener("mousemove", trackPointer)
          document.addEventListener("dragover", trackPointer)
          document.addEventListener("touchmove", trackPointer, { passive: true })
          document.addEventListener("pointermove", trackPointer)
        },
        onEnd: (evt) => {
          document.removeEventListener("mousemove", trackPointer)
          document.removeEventListener("dragover", trackPointer)
          document.removeEventListener("touchmove", trackPointer)
          document.removeEventListener("pointermove", trackPointer)
          this.idListTarget.classList.remove("id-list-drag-outside")

          if (pointerOutside) {
            evt.item.remove()
          }
          this.computeIdPreview()
          this.markDirty()
        }
      })
    }
  }

  onElementTypeChange(event) {
    const selectEl = event.target.closest(".id-part-type")
    if (!selectEl) return

    const row = selectEl.closest(".id-element-row")
    const specInput = row?.querySelector(".id-part-spec")
    if (specInput) {
      const newType = selectEl.value
      const isGuid = newType === "guid"
      specInput.value = DEFAULT_SPECS_BY_TYPE[newType] ?? ""
      specInput.readOnly = isGuid
      specInput.classList.toggle("bg-body-secondary", isGuid)
      specInput.classList.toggle("text-secondary", isGuid)
    }
    this.computeIdPreview()
    this.markDirty()
  }

  addIdElement() {
    if (!this.hasIdListTarget) return
    const rows = this.idListTarget.querySelectorAll(".id-element-row")
    if (rows.length >= 10) {
      window.alert(this.dict.maxElements)
      return
    }
    if (this.hasClearAllInputTarget) this.clearAllInputTarget.value = "0"

    const template = document.getElementById("idElementRowTemplate")
    if (template) {
      const clone = template.content.firstElementChild.cloneNode(true)
      this.idListTarget.appendChild(clone)
      this.initPopovers()
      this.computeIdPreview()
      this.markDirty()
    }
  }

  formatTokenWithAffixes(num, spec, defaultSpec) {
    const raw = (spec || defaultSpec).trim()
    const match = raw.match(/^(.*?)([DXdx]\d+)(.*)$/) ||
                  raw.match(/^(.*?)(?<![A-Za-z])([DXdx])(?![A-Za-z])(.*)$/) ||
                  raw.match(/^([^DXdx]*)([DXdx])(.*)$/)
    if (!match) return String(num)

    const [, prefix, code, suffix] = match
    const digits = parseInt(code.slice(1), 10) || 0
    let core = code.toLowerCase().startsWith("x") ? num.toString(16) : num.toString(10)
    if (digits > 0) core = core.padStart(digits, "0")
    core = code.startsWith("X") ? core.toUpperCase() : core.toLowerCase()
    return `${prefix}${core}${suffix}`
  }

  computeIdPreview() {
    if (!this.hasIdListTarget || !this.hasIdPreviewTarget) return
    const rows = this.idListTarget.querySelectorAll(".id-element-row")
    const nextSeq = parseInt(this.idListTarget.dataset.nextSeq || "1", 10) || 1

    if (rows.length === 0) {
      if (this.hasClearAllInputTarget) this.clearAllInputTarget.value = "1"
      this.idPreviewTarget.textContent = `ITEM-${String(nextSeq).padStart(4, "0")}`
      return
    }

    if (this.hasClearAllInputTarget) this.clearAllInputTarget.value = "0"
    const now = new Date()
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    const parts = Array.from(rows).map((row) => {
      const type = row.querySelector(".id-part-type").value
      const specInput = row.querySelector(".id-part-spec")
      const hintEl = row.querySelector(".id-part-hint")

      if (hintEl) hintEl.textContent = this.dict.hints[type] || ""
      if (specInput) {
        const isGuid = type === "guid"
        specInput.readOnly = isGuid
        specInput.classList.toggle("bg-body-secondary", isGuid)
        specInput.classList.toggle("text-secondary", isGuid)
      }
      const spec = specInput ? specInput.value : ""

      if (type === "fixed") return spec
      if (type === "random_20bit") return this.formatTokenWithAffixes(687674, spec, "X5")
      if (type === "random_32bit") return this.formatTokenWithAffixes(3880747817, spec, "X8")
      if (type === "random_6digit") return this.formatTokenWithAffixes(482910, spec, "D6")
      if (type === "random_9digit") return this.formatTokenWithAffixes(739201845, spec, "D9")
      if (type === "guid") return "550e8400-e29b-41d4-a716-446655440000"
      if (type === "datetime") {
        return (spec || "yyyy")
          .replaceAll("yyyy", String(now.getFullYear()))
          .replaceAll("yy", String(now.getFullYear()).slice(-2))
          .replaceAll("MM", String(now.getMonth() + 1).padStart(2, "0"))
          .replaceAll("ddd", days[now.getDay()])
          .replaceAll("dd", String(now.getDate()).padStart(2, "0"))
          .replaceAll("HH", String(now.getHours()).padStart(2, "0"))
          .replaceAll("mm", String(now.getMinutes()).padStart(2, "0"))
          .replaceAll("ss", String(now.getSeconds()).padStart(2, "0"))
      }
      if (type === "sequence") return this.formatTokenWithAffixes(nextSeq, spec, "D3")
      return ""
    })
    this.idPreviewTarget.textContent = parts.join("") || `ITEM-${String(nextSeq).padStart(4, "0")}`
  }

  initCustomFieldsBuilder() {
    if (!this.hasFieldsListTarget || !window.Sortable) return
    this.fieldsSortable = new window.Sortable(this.fieldsListTarget, {
      handle: ".field-drag-handle",
      animation: 150,
      onEnd: () => {
        this.updateFieldPositions()
        this.markDirty()
      }
    })
  }

  addFieldSlot() {
    if (!this.hasFieldsListTarget || !this.hasFieldTypeSelectTarget) return
    const type = this.fieldTypeSelectTarget.value
    const slot = Array.from(this.fieldsListTarget.querySelectorAll(`.field-slot-row[data-field-type="${type}"]`))
      .find((row) => row.dataset.active === "false")

    if (!slot) {
      window.alert(this.dict.maxFields)
      return
    }
    slot.dataset.active = "true"
    slot.classList.remove("d-none")
    slot.querySelector(".field-state-input").value = "1"
    const nameInput = slot.querySelector("input[name*='[name]']")
    if (nameInput && !nameInput.value.trim()) {
      nameInput.value = slot.dataset.defaultName || "Field"
    }
    this.fieldsListTarget.appendChild(slot)
    this.updateFieldPositions()
    this.markDirty()
  }

  removeFieldSlot(event) {
    const row = event.currentTarget.closest(".field-slot-row")
    if (!row) return
    row.dataset.active = "false"
    row.classList.add("d-none")
    row.querySelector(".field-state-input").value = "0"
    this.markDirty()
  }

  updateFieldPositions() {
    this.fieldsListTarget.querySelectorAll(".field-slot-row").forEach((row, idx) => {
      row.querySelector(".field-position-input").value = idx + 1
    })
  }

  initUserAccessAutocomplete() {
    if (!this.hasUserAccessSelectTarget || !window.TomSelect || this.userAccessSelectTarget.tomselect) return
    this.userTomSelect = new window.TomSelect(this.userAccessSelectTarget, {
      valueField: "email",
      labelField: "label",
      searchField: ["name", "email"],
      maxItems: 1,
      preload: false,
      load: (query, callback) => {
        if (!query || query.trim().length < 2) return callback()
        fetch(`/users/autocomplete?q=${encodeURIComponent(query)}`)
          .then((r) => r.json())
          .then((users) => callback(users))
          .catch(() => callback())
      }
    })
  }

  initPopovers() {
    if (!window.bootstrap) return
    document.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
      const instance = window.bootstrap.Popover.getOrCreateInstance(el, { container: "body" })
      this.popoverInstances.push(instance)
    })
  }
}