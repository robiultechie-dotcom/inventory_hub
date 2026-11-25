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
    commentFailed: "Could not post comment. Please try again.",
    defaultSelectOptions: "Option 1, Option 2",
    fieldLabels: {
      string: "Single-Line Text",
      text: "Multi-Line Text",
      int: "Numeric",
      link: "Document/Image",
      bool: "True/False",
      select: "One From List"
    },
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
    commentFailed: "No se pudo publicar el comentario. Inténtalo de nuevo.",
    defaultSelectOptions: "Opción 1, Opción 2",
    fieldLabels: {
      string: "Texto de una línea",
      text: "Texto multilínea",
      int: "Numérico",
      link: "Documento/Imagen",
      bool: "Verdadero/Falso",
      select: "Lista de opciones"
    },
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
    "headerTitle",
    "headerCategory",
    "headerVisibility",
    "headerDescription",
    "headerTags",
    "accessStatusBadge",
    "publicAccessNotice",
    "discussionList",
    "commentForm",
    "commentInput",
    "commentSubmit",
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
    "idEmptyState",
    "idPreview",
    "clearAllInput",
    "fieldsList",
    "fieldsEmptyState",
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
    this.isSubmittingComment = false
    this.popoverInstances = new Set()

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
    if (this.popoverInstances?.size) {
      this.popoverInstances.forEach((p) => {
        try { p.dispose() } catch (_) {}
      })
      this.popoverInstances.clear()
    }
  }

  saveImmediately() {
    this.markDirty()
    this.performAutoSave()
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

  async flushBeforeFormSubmit(event) {
    if (!this.hasAutoSaveFormTarget) return
    if (!this.activeSavePromise && this.changeCounter <= this.lastSavedCounter) return

    event.preventDefault()
    const form = event.currentTarget
    let saved = await this.performAutoSave()
    if (saved && this.changeCounter > this.lastSavedCounter) {
      saved = await this.performAutoSave()
    }
    if (saved) {
      form.requestSubmit()
    }
  }

  submitItemFilter(event) {
    const form = event.currentTarget?.form || event.currentTarget?.closest("form")
    if (form) form.requestSubmit()
  }

  initDiscussionPolling() {
    if (!this.hasDiscussionListTarget) return
    const url = this.discussionListTarget.dataset.pollUrl

    this.pollTimer = setInterval(async () => {
      try {
        const res = await fetch(url, { headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" } })
        if (res.status === 200 && !res.redirected) {
          const contentType = res.headers.get("content-type") || ""
          if (!contentType.includes("text/html")) return

          const html = await res.text()
          if (this.discussionListTarget.innerHTML.trim() !== html.trim()) {
            this.discussionListTarget.innerHTML = html
          }
          this.updateChatTabCount(res.headers.get("X-Comments-Count"))
        }
      } catch (_) {}
    }, 3000)
  }

  updateChatTabCount(countHeader) {
    if (countHeader === null || countHeader === undefined) return
    const badge = document.getElementById("chatTabCount")
    if (badge) badge.textContent = countHeader
  }

  async submitComment(event) {
    event.preventDefault()
    if (this.isSubmittingComment || !this.hasCommentFormTarget || !this.hasCommentInputTarget) return
    const body = this.commentInputTarget.value.trim()
    if (!body) return

    this.isSubmittingComment = true
    if (this.hasCommentSubmitTarget) this.commentSubmitTarget.disabled = true

    const formData = new FormData(this.commentFormTarget)
    try {
      const res = await fetch(this.commentFormTarget.action, {
        method: "POST",
        headers: {
          Accept: "text/html, application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "X-Requested-With": "XMLHttpRequest"
        },
        body: formData
      })

      if (res.status === 401 || res.redirected) {
        window.location.reload()
        return
      }

      const contentType = res.headers.get("content-type") || ""
      if (res.ok && contentType.includes("text/html")) {
        const html = await res.text()
        if (this.hasDiscussionListTarget) this.discussionListTarget.innerHTML = html
        this.updateChatTabCount(res.headers.get("X-Comments-Count"))
        this.commentInputTarget.value = ""
      } else {
        const errData = await res.json().catch(() => ({}))
        window.alert(errData.error || this.dict.commentFailed)
      }
    } catch (_) {
      window.alert(this.dict.commentFailed)
    } finally {
      this.isSubmittingComment = false
      if (this.hasCommentSubmitTarget) this.commentSubmitTarget.disabled = false
    }
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
      headerBadge.className = "badge bg-warning-subtle text-warning-emphasis border border-warning-subtle rounded-pill px-3 py-1 font-mono"
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

  syncHeaderFromResponse(data) {
    if (this.hasHeaderTitleTarget && data.title) {
      this.headerTitleTarget.textContent = data.title
    }

    if (this.hasHeaderCategoryTarget && data.category_name) {
      this.headerCategoryTarget.innerHTML = ""
      const icon = document.createElement("i")
      icon.className = `bi ${data.category_icon || "bi-box-seam"} me-1 text-primary`
      this.headerCategoryTarget.append(icon, document.createTextNode(data.category_name))
    }

    if (typeof data.is_public === "boolean") {
      const badgeClass = `badge rounded-pill px-3 py-1 ${
        data.is_public
          ? "bg-success-subtle text-success border border-success-subtle"
          : "bg-secondary-subtle text-secondary border border-secondary-subtle"
      }`
      const iconClass = `bi ${data.is_public ? "bi-globe2" : "bi-lock-fill"} me-1`

      if (this.hasHeaderVisibilityTarget) {
        this.headerVisibilityTarget.className = badgeClass
        this.headerVisibilityTarget.innerHTML = ""
        const icon = document.createElement("i")
        icon.className = iconClass
        this.headerVisibilityTarget.append(icon, document.createTextNode(data.visibility_label || ""))
      }

      if (this.hasAccessStatusBadgeTarget) {
        this.accessStatusBadgeTarget.className = badgeClass
        this.accessStatusBadgeTarget.innerHTML = ""
        const icon = document.createElement("i")
        icon.className = iconClass
        this.accessStatusBadgeTarget.append(icon, document.createTextNode(data.visibility_label || ""))
      }

      if (this.hasPublicAccessNoticeTarget) {
        this.publicAccessNoticeTarget.classList.toggle("d-none", !data.is_public)
      }
    }

    if (this.hasHeaderDescriptionTarget && typeof data.description_html === "string") {
      this.headerDescriptionTarget.innerHTML = data.description_html
    }

    if (this.hasHeaderTagsTarget && Array.isArray(data.tags)) {
      this.headerTagsTarget.innerHTML = ""
      this.headerTagsTarget.classList.toggle("d-none", data.tags.length === 0)
      data.tags.forEach((tag) => {
        const link = document.createElement("a")
        link.href = tag.url
        link.className = "tag-pill-cloud tag-weight-1"
        const hash = document.createElement("span")
        hash.className = "text-primary"
        hash.textContent = "#"
        link.append(hash, document.createTextNode(tag.name))
        this.headerTagsTarget.appendChild(link)
      })
    }

    const fieldsCountEl = document.getElementById("fieldsTabCount")
    if (fieldsCountEl && typeof data.active_fields_count === "number") {
      fieldsCountEl.textContent = String(data.active_fields_count)
    }
  }

  syncSavedCustomFieldIds(savedFields) {
    if (!this.hasFieldsListTarget || !Array.isArray(savedFields)) return

    const rows = Array.from(this.fieldsListTarget.querySelectorAll(".dynamic-field-row"))
    const assignedIds = new Set(
      rows.map((row) => row.querySelector(".field-id-input")?.value?.trim()).filter(Boolean)
    )
    const unassignedServerFields = savedFields.filter((cf) => !assignedIds.has(String(cf.id)))

    rows.forEach((row) => {
      const idInput = row.querySelector(".field-id-input")
      if (!idInput || idInput.value.trim()) return

      const rowType = row.querySelector(".field-type-select")?.value
      const matchIdx = unassignedServerFields.findIndex((cf) => cf.field_type === rowType)
      if (matchIdx !== -1) {
        const [matched] = unassignedServerFields.splice(matchIdx, 1)
        idInput.value = String(matched.id)
      }
    })
  }

  async executeAutoSaveRequest() {
    if (this.hasFieldsListTarget) {
      this.reindexDynamicFields()
    }
    if (this.tagTomSelect && this.hasTagInputTarget) {
      this.tagInputTarget.value = this.tagTomSelect.getValue()
    }
    if (this.mdeInstance && this.hasMarkdownInputTarget) {
      this.markdownInputTarget.value = this.mdeInstance.value()
    }

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

        this.syncSavedCustomFieldIds(data.custom_fields)
        this.syncHeaderFromResponse(data)

        if (headerBadge) {
          if (this.changeCounter > this.lastSavedCounter) {
            headerBadge.className = "badge bg-warning-subtle text-warning-emphasis border border-warning-subtle rounded-pill px-3 py-1 font-mono"
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
    const existing = Array.from(
      new Set(this.tagInputTarget.value.split(",").map((t) => t.trim()).filter(Boolean))
    )
    this.tagInputTarget.value = existing.join(",")

    let initializing = true
    this.tagTomSelect = new window.TomSelect(this.tagInputTarget, {
      plugins: ["remove_button"],
      delimiter: ",",
      maxItems: null,
      persist: false,
      create: true,
      valueField: "name",
      labelField: "name",
      searchField: "name",
      options: existing.map((name) => ({ name })),
      items: existing,
      load: (query, callback) => {
        fetch(`/tags/autocomplete?q=${encodeURIComponent(query)}`)
          .then((r) => r.json())
          .then((names) => callback(names.map((name) => ({ name }))))
          .catch(() => callback())
      },
      onChange: () => {
        if (!initializing) this.markDirty()
      }
    })

    existing.forEach((name) => {
      if (!this.tagTomSelect.options[name]) {
        this.tagTomSelect.addOption({ name })
      }
      if (!this.tagTomSelect.items.includes(name)) {
        this.tagTomSelect.addItem(name, true)
      }
    })
    initializing = false
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
        draggable: ".id-element-row",
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
            this.disposePopoversWithin(evt.item)
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

  removeIdElement(event) {
    const row = event.currentTarget.closest(".id-element-row")
    if (!row) return
    this.disposePopoversWithin(row)
    row.remove()
    this.computeIdPreview()
    this.markDirty()
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

    if (this.hasIdEmptyStateTarget) {
      this.idEmptyStateTarget.classList.toggle("d-none", rows.length > 0)
    }

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
    if (!this.hasFieldsListTarget) return
    this.reindexDynamicFields()

    if (window.Sortable) {
      this.fieldsSortable = new window.Sortable(this.fieldsListTarget, {
        handle: ".field-drag-handle",
        draggable: ".dynamic-field-row",
        animation: 150,
        onEnd: () => {
          this.reindexDynamicFields()
          this.markDirty()
        }
      })
    }
  }

  addDynamicField() {
    if (!this.hasFieldsListTarget || !this.hasFieldTypeSelectTarget) return
    const template = document.getElementById("dynamicFieldRowTemplate")
    if (!template) return

    const fieldType = this.fieldTypeSelectTarget.value || "string"
    const clone = template.content.firstElementChild.cloneNode(true)
    const nextNumber = this.fieldsListTarget.querySelectorAll(".dynamic-field-row").length + 1

    const typeSelect = clone.querySelector(".field-type-select")
    if (typeSelect) typeSelect.value = fieldType

    const nameInput = clone.querySelector(".field-name-input")
    if (nameInput) {
      const label = this.dict.fieldLabels[fieldType] || "Field"
      nameInput.value = `${label} #${nextNumber}`
    }

    if (fieldType === "select") {
      const optionsInput = clone.querySelector(".field-select-options-input")
      if (optionsInput && !optionsInput.value.trim()) {
        optionsInput.value = this.dict.defaultSelectOptions
      }
    }

    this.toggleTuningPanelsForRow(clone, fieldType)
    this.fieldsListTarget.appendChild(clone)
    this.reindexDynamicFields()
    this.markDirty()

    if (nameInput) {
      nameInput.focus()
      nameInput.select()
    }
  }

  removeDynamicField(event) {
    const row = event.currentTarget.closest(".dynamic-field-row")
    if (!row) return
    row.remove()
    this.reindexDynamicFields()
    this.markDirty()
  }

  onDynamicFieldTypeChange(event) {
    const selectEl = event.currentTarget
    const row = selectEl.closest(".dynamic-field-row")
    if (!row) return

    const newType = selectEl.value
    if (newType === "select") {
      const optionsInput = row.querySelector(".field-select-options-input")
      if (optionsInput && !optionsInput.value.trim()) {
        optionsInput.value = this.dict.defaultSelectOptions
      }
    }

    this.toggleTuningPanelsForRow(row, newType)
    this.markDirty()
  }

  toggleTuningPanelsForRow(row, fieldType) {
    const isText = fieldType === "string" || fieldType === "text"
    const isNumeric = fieldType === "int"
    const isSelect = fieldType === "select"

    const strip = row.querySelector(".tuning-strip")
    const textGroup = row.querySelector(".tuning-text-group")
    const numGroup = row.querySelector(".tuning-numeric-group")
    const selGroup = row.querySelector(".tuning-select-group")

    if (strip) strip.classList.toggle("d-none", !(isText || isNumeric || isSelect))
    if (textGroup) textGroup.classList.toggle("d-none", !isText)
    if (numGroup) numGroup.classList.toggle("d-none", !isNumeric)
    if (selGroup) selGroup.classList.toggle("d-none", !isSelect)
  }

  reindexDynamicFields() {
    if (!this.hasFieldsListTarget) return
    const rows = Array.from(this.fieldsListTarget.querySelectorAll(".dynamic-field-row"))

    if (this.hasFieldsEmptyStateTarget) {
      this.fieldsEmptyStateTarget.classList.toggle("d-none", rows.length > 0)
    }

    rows.forEach((row, idx) => {
      const posInput = row.querySelector(".field-position-input")
      if (posInput) posInput.value = String(idx + 1)

      row.querySelectorAll("[name]").forEach((el) => {
        const currentName = el.getAttribute("name")
        if (currentName && currentName.startsWith("custom_fields[")) {
          el.setAttribute("name", currentName.replace(/^custom_fields\[[^\]]+\]/, `custom_fields[${idx}]`))
        }
      })

      const cb = row.querySelector(".field-show-checkbox")
      const lbl = row.querySelector(".field-show-label")
      const checkboxId = `tbl_cf_${idx}`
      if (cb) cb.id = checkboxId
      if (lbl) lbl.setAttribute("for", checkboxId)
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
      this.popoverInstances.add(instance)
    })
  }

  disposePopoversWithin(container) {
    if (!window.bootstrap || !container) return
    container.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
      const instance = window.bootstrap.Popover.getInstance(el)
      if (instance) {
        this.popoverInstances.delete(instance)
        try { instance.dispose() } catch (_) {}
      }
    })
  }
}