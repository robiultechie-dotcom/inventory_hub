import "@hotwired/turbo-rails"
import "controllers"

if (window.Dropzone) {
  window.Dropzone.autoDiscover = false
}

// Fix F2: Implement global toggleItemLike used by TableSelectionController toolbar
window.toggleItemLike = async function(likeUrl, rowElement = null) {
  if (!likeUrl) return null

  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  const res = await fetch(likeUrl, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "X-CSRF-Token": csrfToken,
      "X-Requested-With": "XMLHttpRequest"
    }
  })

  if (!res.ok) return null
  const data = await res.json().catch(() => null)
  if (!data) return null

  const row = rowElement || document.querySelector(`tr[data-like-url="${CSS.escape(likeUrl)}"]`)
  if (row) {
    row.dataset.likes = String(data.likes_count)

    const countEl = row.querySelector("[data-like-count]")
    if (countEl) countEl.textContent = String(data.likes_count)

    const badgeEl = row.querySelector("[data-like-badge]")
    if (badgeEl) {
      badgeEl.classList.toggle("bg-danger-subtle", Boolean(data.liked))
      badgeEl.classList.toggle("text-danger", Boolean(data.liked))
      badgeEl.classList.toggle("border-danger-subtle", Boolean(data.liked))
      badgeEl.classList.toggle("bg-body-tertiary", !data.liked)
      badgeEl.classList.toggle("text-secondary", !data.liked)
      badgeEl.classList.remove("like-pop-anim")
      void badgeEl.offsetWidth
      badgeEl.classList.add("like-pop-anim")
    }

    const iconEl = row.querySelector("[data-like-icon]")
    if (iconEl) {
      iconEl.classList.toggle("bi-heart-fill", Boolean(data.liked))
      iconEl.classList.toggle("bi-heart", !data.liked)
    }
  }

  return data
}

// Zero-dependency Native Cloud Uploader: Direct Cloudinary OR authenticated server-side /uploads
window.mountCloudDropzone = function(element, options = {}) {
  if (!element) return null
  if (element.dropzone && typeof element.dropzone.destroy === "function") {
    element.dropzone.destroy()
  }

  const isEs = document.documentElement.lang === "es"
  const idleHtml = isEs
    ? '<i class="bi bi-cloud-arrow-up fs-4 d-block mb-1 text-primary"></i><span class="small fw-medium d-block">Arrastra una imagen aquí o haz clic para subir</span><span class="text-secondary" style="font-size: 0.75rem;">JPG, PNG, WebP o GIF (máx. 5 MB)</span>'
    : '<i class="bi bi-cloud-arrow-up fs-4 d-block mb-1 text-primary"></i><span class="small fw-medium d-block">Drop image here or click to upload</span><span class="text-secondary" style="font-size: 0.75rem;">JPG, PNG, WebP, or GIF (max 5 MB)</span>'
  const uploadingHtml = isEs
    ? '<div class="spinner-border spinner-border-sm text-primary mb-2" role="status"></div><span class="small fw-medium d-block">Subiendo imagen a la nube...</span>'
    : '<div class="spinner-border spinner-border-sm text-primary mb-2" role="status"></div><span class="small fw-medium d-block">Uploading image to cloud...</span>'
  const unconfiguredMessage = isEs
    ? '<div class="text-center text-secondary py-2"><i class="bi bi-cloud-slash fs-4 d-block mb-1"></i><span class="small">Configura CLOUDINARY_URL o CLOUDINARY_CLOUD_NAME y CLOUDINARY_UPLOAD_PRESET para subir imágenes.</span></div>'
    : '<div class="text-center text-secondary py-2"><i class="bi bi-cloud-slash fs-4 d-block mb-1"></i><span class="small">Set CLOUDINARY_URL or CLOUDINARY_CLOUD_NAME & CLOUDINARY_UPLOAD_PRESET to enable cloud uploads.</span></div>'
  const fallbackUploadError = isEs ? "Error al subir la imagen" : "Upload failed"
  const invalidTypeMsg = isEs ? "Solo se permiten imágenes JPG, PNG, WebP o GIF." : "Only JPG, PNG, WebP, or GIF images are allowed."
  const tooLargeMsg = isEs ? "La imagen debe pesar menos de 5 MB." : "Image size must be under 5 MB."

  if (options.removeBtn) {
    options.removeBtn.onclick = () => {
      if (options.hiddenInput) options.hiddenInput.value = ""
      if (options.previewImg) options.previewImg.src = ""
      if (options.previewCard) options.previewCard.classList.add("d-none")
      if (typeof options.onRemoved === "function") options.onRemoved()
    }
  }

  const cloudName = document.querySelector('meta[name="cloudinary-cloud-name"]')?.content?.trim()
  const uploadPreset = document.querySelector('meta[name="cloudinary-upload-preset"]')?.content?.trim()
  const serverUploadEnabled = document.querySelector('meta[name="server-upload-enabled"]')?.content === "true"
  const useDirectCloudinary = Boolean(cloudName && uploadPreset)

  if (!useDirectCloudinary && !serverUploadEnabled) {
    element.classList.remove("dropzone", "dz-clickable", "dz-drag-hover")
    element.removeAttribute("role")
    element.removeAttribute("tabindex")
    element.innerHTML = unconfiguredMessage
    return null
  }

  element.classList.add("dropzone", "dz-clickable")
  element.setAttribute("role", "button")
  element.setAttribute("tabindex", "0")
  element.innerHTML = `<div class="dz-message text-center w-100">${idleHtml}</div>`

  const messageEl = element.querySelector(".dz-message")
  const fileInput = document.createElement("input")
  fileInput.type = "file"
  fileInput.accept = "image/jpeg,image/png,image/webp,image/gif"
  fileInput.className = "d-none"
  element.appendChild(fileInput)

  const allowedTypes = new Set(["image/jpeg", "image/jpg", "image/png", "image/webp", "image/gif"])
  const maxBytes = 5 * 1024 * 1024
  let isUploading = false

  const uploadFile = async (file) => {
    if (!file || isUploading) return

    const fileType = (file.type || "").toLowerCase()
    if (fileType && !allowedTypes.has(fileType)) {
      window.alert(invalidTypeMsg)
      fileInput.value = ""
      return
    }
    if (file.size > maxBytes) {
      window.alert(tooLargeMsg)
      fileInput.value = ""
      return
    }

    isUploading = true
    element.classList.add("is-uploading")
    messageEl.innerHTML = uploadingHtml

    try {
      const formData = new FormData()
      formData.append("file", file)

      const endpoint = useDirectCloudinary
        ? `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/upload`
        : "/uploads"

      const headers = { Accept: "application/json" }
      if (useDirectCloudinary) {
        formData.append("upload_preset", uploadPreset)
      } else {
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        if (csrfToken) headers["X-CSRF-Token"] = csrfToken
        headers["X-Requested-With"] = "XMLHttpRequest"
      }

      const response = await fetch(endpoint, { method: "POST", headers, body: formData })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        throw new Error(data?.error?.message || data?.error || fallbackUploadError)
      }

      const uploadedUrl = data?.secure_url || data?.url
      if (!uploadedUrl) throw new Error(fallbackUploadError)

      if (options.hiddenInput) options.hiddenInput.value = uploadedUrl
      if (options.previewImg) options.previewImg.src = uploadedUrl
      if (options.previewCard) options.previewCard.classList.remove("d-none")
      if (typeof options.onUploaded === "function") options.onUploaded(uploadedUrl)
    } catch (err) {
      window.alert(err?.message || fallbackUploadError)
    } finally {
      isUploading = false
      element.classList.remove("is-uploading")
      messageEl.innerHTML = idleHtml
      fileInput.value = ""
    }
  }

  const onClick = (e) => {
    if (e.target !== fileInput && !isUploading) fileInput.click()
  }
  const onKeyDown = (e) => {
    if ((e.key === "Enter" || e.key === " ") && !isUploading) {
      e.preventDefault()
      fileInput.click()
    }
  }
  const onFileChange = () => {
    if (fileInput.files && fileInput.files[0]) uploadFile(fileInput.files[0])
  }
  const onDragOver = (e) => {
    e.preventDefault()
    if (!isUploading) element.classList.add("dz-drag-hover")
  }
  const onDragLeave = (e) => {
    e.preventDefault()
    element.classList.remove("dz-drag-hover")
  }
  const onDrop = (e) => {
    e.preventDefault()
    element.classList.remove("dz-drag-hover")
    const file = e.dataTransfer?.files?.[0]
    if (file) uploadFile(file)
  }

  element.addEventListener("click", onClick)
  element.addEventListener("keydown", onKeyDown)
  fileInput.addEventListener("change", onFileChange)
  element.addEventListener("dragover", onDragOver)
  element.addEventListener("dragleave", onDragLeave)
  element.addEventListener("drop", onDrop)

  const controller = {
    destroy() {
      element.removeEventListener("click", onClick)
      element.removeEventListener("keydown", onKeyDown)
      fileInput.removeEventListener("change", onFileChange)
      element.removeEventListener("dragover", onDragOver)
      element.removeEventListener("dragleave", onDragLeave)
      element.removeEventListener("drop", onDrop)
      element.dropzone = null
    }
  }

  element.dropzone = controller
  return controller
}

function initAuthModalControls() {
  document.querySelectorAll("[data-auth-switch]").forEach((btn) => {
    btn.onclick = () => {
      const target = btn.dataset.authSwitch
      const signInView = document.getElementById("authSignInView")
      const registerView = document.getElementById("authRegisterView")
      const heading = document.getElementById("authModalHeading")
      if (!signInView || !registerView) return

      const showRegister = target === "register"
      signInView.classList.toggle("d-none", showRegister)
      registerView.classList.toggle("d-none", !showRegister)
      if (heading) {
        heading.textContent = showRegister ? heading.dataset.registerTitle : heading.dataset.signinTitle
      }
    }
  })

  document.querySelectorAll("[data-pw-toggle]").forEach((btn) => {
    btn.onclick = () => {
      const input = document.getElementById(btn.dataset.pwToggle)
      if (!input) return
      const isPassword = input.type === "password"
      input.type = isPassword ? "text" : "password"
      btn.innerHTML = `<i class="bi ${isPassword ? "bi-eye-slash" : "bi-eye"}"></i>`
    }
  })
}

function mountModalDropzoneIfNeeded() {
  const dzEl = document.getElementById("modalDropzone")
  if (dzEl && !dzEl.dropzone) {
    window.mountCloudDropzone(dzEl, {
      hiddenInput: document.getElementById("modalInventoryImageUrl"),
      previewCard: document.getElementById("modalImagePreviewCard"),
      previewImg: document.getElementById("modalImagePreviewImg"),
      removeBtn: document.getElementById("modalRemoveImgBtn")
    })
  }
}

function initNewInventoryModal() {
  const modalEl = document.getElementById("newInventoryModal")
  if (!modalEl) return

  // Mount dropzone immediately so it is visible as soon as the modal opens
  mountModalDropzoneIfNeeded()

  if (modalEl._inventoryModalInitialized) return
  modalEl._inventoryModalInitialized = true

  modalEl.addEventListener("shown.bs.modal", () => {
    mountModalDropzoneIfNeeded()

    const tagInput = document.getElementById("modalTagInput")
    if (tagInput && window.TomSelect && !tagInput.tomselect) {
      new window.TomSelect(tagInput, {
        plugins: ["remove_button"],
        persist: false,
        create: true,
        valueField: "name",
        labelField: "name",
        searchField: "name",
        load: (query, callback) => {
          fetch(`/tags/autocomplete?q=${encodeURIComponent(query)}`)
            .then((r) => r.json())
            .then((names) => callback(names.map((name) => ({ name }))))
            .catch(() => callback())
        }
      })
    }

    const descInput = document.getElementById("modalDescInput")
    if (descInput && window.EasyMDE) {
      if (!descInput._mdeInstance) {
        const mde = new window.EasyMDE({
          element: descInput,
          spellChecker: false,
          status: false,
          minHeight: "100px",
          toolbar: ["bold", "italic", "heading", "|", "code", "quote", "unordered-list", "ordered-list", "|", "link", "preview"]
        })
        mde.codemirror.on("change", () => {
          descInput.value = mde.value()
        })
        descInput._mdeInstance = mde
      }
      // Fix G3: Refresh CodeMirror layout whenever modal opens
      setTimeout(() => descInput._mdeInstance?.codemirror?.refresh(), 40)
    }
  })
}

// Fix G3: Clean up open Bootstrap modals, dropzones & backdrops before Turbo caches a page
document.addEventListener("turbo:before-cache", () => {
  const dzEl = document.getElementById("modalDropzone")
  if (dzEl?.dropzone && typeof dzEl.dropzone.destroy === "function") {
    dzEl.dropzone.destroy()
  }

  document.querySelectorAll(".modal.show").forEach((modalEl) => {
    window.bootstrap?.Modal?.getInstance(modalEl)?.hide()
    modalEl.classList.remove("show")
    modalEl.style.display = "none"
  })
  document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove())
  document.body.classList.remove("modal-open")
  document.body.style.removeProperty("overflow")
  document.body.style.removeProperty("padding-right")
})

document.addEventListener("turbo:load", () => {
  initAuthModalControls()
  initNewInventoryModal()

  if (window.bootstrap) {
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
      window.bootstrap.Tooltip.getOrCreateInstance(el)
    })
  }
})