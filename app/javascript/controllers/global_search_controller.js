import { Controller } from "@hotwired/stimulus"

const SEARCH_I18N = {
  en: {
    groupSearch: "Full-Text Search",
    groupInventories: "Inventories",
    groupItems: "Items",
    groupTags: "Tags",
    searchAll: (q) => `Search all results for "${q}"`,
    pressEnter: "Press Enter to view full tables",
    invCount: (c) => `${c} inventories`
  },
  es: {
    groupSearch: "Búsqueda de Texto Completo",
    groupInventories: "Inventarios",
    groupItems: "Artículos",
    groupTags: "Etiquetas",
    searchAll: (q) => `Buscar todos los resultados para "${q}"`,
    pressEnter: "Presiona Enter para ver las tablas completas",
    invCount: (c) => `${c} inventarios`
  }
}

export default class extends Controller {
  static targets = ["input"]
  static values = { url: String }

  connect() {
    if (!this.hasInputTarget || !window.TomSelect || this.inputTarget.tomselect) return

    const dict = SEARCH_I18N[document.documentElement.lang === "es" ? "es" : "en"]
    const self = this

    this.tomselect = new window.TomSelect(this.inputTarget, {
      valueField: "url",
      labelField: "title",
      searchField: ["title", "subtitle"],
      maxItems: 1,
      create: false,
      preload: "focus",
      optgroupField: "group",
      optgroups: [
        { value: "search", label: dict.groupSearch },
        { value: "inventories", label: dict.groupInventories },
        { value: "items", label: dict.groupItems },
        { value: "tags", label: dict.groupTags }
      ],
      load: (query, callback) => {
        const endpoint = `${self.urlValue}?q=${encodeURIComponent(query || "")}`
        fetch(endpoint)
          .then((r) => r.json())
          .then((data) => {
            const options = []
            if (query && query.trim().length > 0) {
              options.push({
                url: `/search?q=${encodeURIComponent(query.trim())}`,
                title: dict.searchAll(query.trim()),
                subtitle: dict.pressEnter,
                group: "search"
              })
            }
            ;(data.inventories || []).forEach((inv) => {
              options.push({
                url: inv.url,
                title: inv.title,
                subtitle: `${inv.category} • ${inv.creator} (${inv.items_count})`,
                group: "inventories"
              })
            })
            ;(data.items || []).forEach((item) => {
              options.push({
                url: item.url,
                title: `${item.custom_id} — ${item.label}`,
                subtitle: item.inventory_title,
                group: "items"
              })
            })
            ;(data.tags || []).forEach((tag) => {
              options.push({
                url: tag.url,
                title: `#${tag.name}`,
                subtitle: dict.invCount(tag.count),
                group: "tags"
              })
            })
            callback(options)
          })
          .catch(() => callback())
      },
      render: {
        option: (item, escape) => `
          <div class="py-1 px-2 d-flex justify-content-between align-items-center gap-2">
            <span class="fw-semibold small text-truncate">${escape(item.title)}</span>
            <span class="text-secondary font-mono text-nowrap" style="font-size: 0.72rem;">${escape(item.subtitle || "")}</span>
          </div>
        `
      },
      onFocus: () => this.updateHintVisibility(true),
      onBlur: () => this.updateHintVisibility(false),
      onType: () => this.updateHintVisibility(true),
      onChange: (value) => {
        if (value) window.location.href = value
      }
    })

    this.tomselect.control_input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && this.tomselect.inputValue().trim().length > 0 && !this.tomselect.getValue()) {
        e.preventDefault()
        window.location.href = `/search?q=${encodeURIComponent(this.tomselect.inputValue().trim())}`
      } else if (e.key === "Escape") {
        this.tomselect.blur()
      }
    })

    // Fix F5: Global '/' keyboard shortcut to focus search bar
    this.shortcutHandler = (e) => {
      if (e.key !== "/" || e.ctrlKey || e.metaKey || e.altKey) return
      const target = e.target
      const tag = target?.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || target?.isContentEditable || target?.closest?.(".CodeMirror")) {
        return
      }
      e.preventDefault()
      this.tomselect?.focus()
    }
    document.addEventListener("keydown", this.shortcutHandler)
  }

  updateHintVisibility(isFocused) {
    const hasText = Boolean(this.tomselect?.inputValue()?.trim()?.length)
    this.element.classList.toggle("is-active", isFocused || hasText)
  }

  disconnect() {
    if (this.shortcutHandler) {
      document.removeEventListener("keydown", this.shortcutHandler)
      this.shortcutHandler = null
    }
    if (this.tomselect) {
      this.tomselect.destroy()
      this.tomselect = null
    }
  }
}