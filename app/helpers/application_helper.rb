# frozen_string_literal: true

module ApplicationHelper
  ALLOWED_MARKDOWN_TAGS = %w[p br strong em b i code pre ul ol li blockquote a h1 h2 h3 h4 h5 h6 hr span].freeze
  ALLOWED_MARKDOWN_ATTRIBUTES = %w[href title target rel class].freeze

  def render_markdown(text)
    return "".html_safe if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      filter_html:     true,
      no_styles:       true,
      safe_links_only: true,
      hard_wrap:       true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )
    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink:           true,
      fenced_code_blocks: true,
      tables:             true,
      strikethrough:      true
    )
    sanitize(markdown.render(text.to_s), tags: ALLOWED_MARKDOWN_TAGS, attributes: ALLOWED_MARKDOWN_ATTRIBUTES)
  end

  def category_icon_class(category_name)
    case category_name.to_s.downcase
    when "equipment" then "bi-cpu"
    when "furniture" then "bi-lamp"
    when "book"      then "bi-journal-bookmark"
    else                  "bi-box-seam"
    end
  end

  def localized_category_name(category)
    return "—" unless category

    key = category.name.to_s.downcase
    I18n.t("categories.#{key}", default: category.name)
  end

  def localized_id_element_label(key, fallback = nil)
    I18n.t("inventory.id_elements.#{key}", default: fallback || key.to_s.humanize)
  end

  def localized_field_type_label(type_key, fallback = nil)
    I18n.t("inventory.field_slot_labels.#{type_key}", default: fallback || type_key.to_s.humanize)
  end

  # Uses static_preview: true so zero database queries run inside table loops (Section 14)
  def inventory_id_preview(inventory)
    CustomIdGenerator.new(inventory).generate(preview: true, static_preview: true)
  end

  def user_initials(name)
    parts = name.to_s.strip.split(/\s+/)
    return "U" if parts.empty?

    parts.first(2).map { |p| p[0].upcase }.join
  end

  def localized_time_ago(timestamp)
    return "—" unless timestamp

    I18n.t("common.time_ago", time: time_ago_in_words(timestamp))
  end

  def tag_cloud_weight_class(tag, max_count)
    return "tag-weight-1" if max_count.to_i <= 1

    ratio = tag.inventories_count.to_f / max_count.to_f
    if ratio >= 0.85    then "tag-weight-5"
    elsif ratio >= 0.65 then "tag-weight-4"
    elsif ratio >= 0.45 then "tag-weight-3"
    elsif ratio >= 0.25 then "tag-weight-2"
    else                     "tag-weight-1"
    end
  end
end