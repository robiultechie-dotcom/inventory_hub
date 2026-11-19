import "@hotwired/turbo-rails"
import "controllers"

if (window.Dropzone) {
  window.Dropzone.autoDiscover = false
}

window.mountCloudDropzone = function(element, options = {}) {
  if (!element || !window.Dropzone) return null
  if (element.dropzone) element.dropzone.destroy()

  const isEs = document.documentElement.lang === "es"
  const dropMessage = isEs
    ? '<i class="bi bi-cloud-arrow-up fs-4 d-block mb-1 text-primary"></i><span class="small fw-medium">Arrastra una imagen aquí o haz clic para subir</span>'
    : '<i class="bi bi-cloud-arrow-up fs-4 d-block mb-1 text-primary"></i><span class="small fw-medium">Drop image here or click to upload</span>'
  const unconfiguredMessage = isEs
    ? '<div class="text-center text-secondary py-2"><i class="bi bi-cloud-slash fs-4 d-block mb-1"></i><span class="small">Configura CLOUDINARY_CLOUD_NAME y CLOUDINARY_UPLOAD_PRESET para subir imágenes directamente a la nube.</span></div>'
    : '<div class="text-center text-secondary py-2"><i class="bi bi-cloud-slash fs-4 d-block mb-1"></i><span class="small">Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET to enable direct cloud image uploads.</span></div>'
  const fallbackUploadError = isEs ? "Error al subir la imagen" : "Upload failed"

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

  if (!cloudName || !uploadPreset) {
    element.innerHTML = unconfiguredMessage
    return null
  }

  element.innerHTML = ""
  const endpoint = `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/upload`

  return new window.Dropzone(element, {
    url: endpoint,
    paramName: "file",
    maxFiles: 1,
    maxFilesize: 5,
    acceptedFiles: "image/jpeg,image/png,image/webp,image/gif",
    dictDefaultMessage: dropMessage,
    init() {
      this.on("sending", (_file, _xhr, formData) => {
        formData.append("upload_preset", uploadPreset)
      })

      this.on("success", (_file, response) => {
        const uploadedUrl = response?.secure_url || response?.url
        if (!uploadedUrl) return

        if (options.hiddenInput) options.hiddenInput.value = uploadedUrl
        if (options.previewImg) options.previewImg.src = uploadedUrl
        if (options.previewCard) options.previewCard.classList.remove("d-none")
        this.removeAllFiles()
        if (typeof options.onUploaded === "function") options.onUploaded(uploadedUrl)
      })

      this.on("error", (file, errorMessage) => {
        const msg = typeof errorMessage === "string"
          ? errorMessage
          : (errorMessage?.error?.message || errorMessage?.error || fallbackUploadError)
        window.alert(msg)
        this.removeFile(file)
      })
    }
  })
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

function initNewInventoryModal() {
  const modalEl = document.getElementById("newInventoryModal")
  if (!modalEl || modalEl.dataset.initialized === "true") return
  modalEl.dataset.initialized = "true"

  modalEl.addEventListener("shown.bs.modal", () => {
    const dzEl = document.getElementById("modalDropzone")
    if (dzEl && !dzEl.dropzone) {
      window.mountCloudDropzone(dzEl, {
        hiddenInput: document.getElementById("modalInventoryImageUrl"),
        previewCard: document.getElementById("modalImagePreviewCard"),
        previewImg: document.getElementById("modalImagePreviewImg"),
        removeBtn: document.getElementById("modalRemoveImgBtn")
      })
    }

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
    if (descInput && window.EasyMDE && !descInput.dataset.mdeInitialized) {
      descInput.dataset.mdeInitialized = "true"
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
    }
  })
}

document.addEventListener("turbo:load", () => {
  initAuthModalControls()
  initNewInventoryModal()

  if (window.bootstrap) {
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
      window.bootstrap.Tooltip.getOrCreateInstance(el)
    })
  }
})