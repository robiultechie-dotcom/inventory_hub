# frozen_string_literal: true

require "csv"
require "caxlsx"

class InventoryExporter
  UTF8_BOM        = "\uFEFF"
  CSV_MIME_TYPE   = "text/csv; charset=utf-8"
  EXCEL_MIME_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  def self.inventories_to_csv(inventories)
    csv_body = CSV.generate(headers: true) do |csv|
      csv << [
        I18n.t("export.headers.id"),
        I18n.t("export.headers.title"),
        I18n.t("export.headers.category"),
        I18n.t("export.headers.creator"),
        I18n.t("export.headers.public"),
        I18n.t("export.headers.items_count"),
        I18n.t("export.headers.created_at")
      ]

      inventories.each do |inv|
        csv << [
          inv.id,
          inv.title,
          inv.category.name,
          inv.creator.name,
          inv.is_public? ? I18n.t("common.true_yes") : I18n.t("common.false_no"),
          inv.items_count,
          inv.created_at.iso8601
        ]
      end
    end

    UTF8_BOM + csv_body
  end

  def initialize(inventory)
    @inventory = inventory
    @fields    = inventory.ordered_custom_fields
    @items     = inventory.items.includes(:created_by, :item_field_values).order(created_at: :asc).to_a
  end

  def to_csv
    csv_body = CSV.generate(headers: true) do |csv|
      csv << item_headers
      @items.each do |item|
        csv << build_item_row(item, for_excel: false)
      end
    end

    UTF8_BOM + csv_body
  end

  def to_xlsx
    package = Axlsx::Package.new
    package.use_shared_strings = true
    workbook = package.workbook

    header_style = workbook.styles.add_style(
      b:         true,
      bg_color:  "4F46E5",
      fg_color:  "FFFFFF",
      alignment: { horizontal: :left, vertical: :center }
    )

    workbook.add_worksheet(name: sanitized_sheet_name) do |sheet|
      sheet.add_row(item_headers, style: header_style)

      @items.each do |item|
        sheet.add_row(build_item_row(item, for_excel: true))
      end

      sheet.sheet_view.pane do |pane|
        pane.state   = :frozen
        pane.y_split = 1
      end
    end

    package.to_stream.read
  end

  private

  def item_headers
    [
      I18n.t("export.headers.custom_id"),
      I18n.t("export.headers.creator"),
      I18n.t("export.headers.created_at"),
      I18n.t("export.headers.likes")
    ] + @fields.map(&:name)
  end

  def build_item_row(item, for_excel:)
    row = [
      item.custom_id,
      item.created_by.name,
      item.created_at.strftime("%Y-%m-%d %H:%M:%S"),
      item.likes_count
    ]

    @fields.each do |field|
      row << format_cell_value(field, item.value_for(field), for_excel: for_excel)
    end

    row
  end

  def format_cell_value(field, val, for_excel:)
    if field.boolean?
      return val ? I18n.t("common.true_yes") : I18n.t("common.false_no")
    end

    return nil if val.nil? || val == ""

    if field.numeric?
      dec = val.is_a?(BigDecimal) ? val : BigDecimal(val.to_s)
      if for_excel
        dec.frac.zero? ? dec.to_i : dec.to_f
      else
        dec.frac.zero? ? dec.to_i.to_s : dec.to_s("F").sub(/\.?0+\z/, "")
      end
    else
      val.to_s
    end
  rescue ArgumentError
    val.to_s
  end

  # Excel worksheet titles cannot exceed 31 chars or contain : \ / ? * [ ]
  def sanitized_sheet_name
    cleaned = @inventory.title.to_s.gsub(%r{[:\\/?*\[\]]}, " ").squish.first(31)
    cleaned.presence || "Items"
  end
end
