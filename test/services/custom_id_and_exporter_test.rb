# frozen_string_literal: true

require "test_helper"
require "csv"

class CustomIdAndExporterTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(name: "Service Category #{SecureRandom.hex(4)}")
    @owner = User.create!(
      name: "Service Owner",
      email: "service-owner-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "confirmed:service-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @inventory = Inventory.create!(
      title: "Parts: Main/Lab [2026] Ultra Long Inventory Name",
      category: @category,
      creator: @owner
    )
  end

  test "generates and validates all 8 custom ID element types including Unicode emoji" do
    @inventory.update!(
      custom_id_config: [
        { "type" => "fixed", "value" => "\u{1F4E6}-", "format" => "" },
        { "type" => "random_20bit", "value" => "", "format" => "X5_" },
        { "type" => "random_32bit", "value" => "", "format" => "X8_" },
        { "type" => "random_6digit", "value" => "", "format" => "D6_" },
        { "type" => "random_9digit", "value" => "", "format" => "D9_" },
        { "type" => "guid", "value" => "", "format" => "" },
        { "type" => "datetime", "value" => "", "format" => "-yyyyMMdd-ddd-" },
        { "type" => "sequence", "value" => "", "format" => "D3" }
      ]
    )

    generator = CustomIdGenerator.new(@inventory)
    fixed_time = Time.utc(2026, 11, 26, 10, 30, 0)
    generated = generator.generate(preview: false, timestamp: fixed_time)

    assert generated.start_with?("\u{1F4E6}-")
    assert_includes generated, "-20261126-Thu-"
    assert generated.end_with?("-001")
    assert generator.valid_format?(generated)
    assert_not generator.valid_format?("BAD-ID-123")
  end

  test "increments sequence from highest existing number even with gaps and enforces new format on edit" do
    @inventory.items.create!(created_by: @owner, custom_id: "ITEM-0001")
    @inventory.items.create!(created_by: @owner, custom_id: "ITEM-0007")

    generator = CustomIdGenerator.new(@inventory)
    assert_equal 8, generator.next_sequence_number
    assert_equal "ITEM-0008", generator.generate(preview: false)

    existing_item = @inventory.items.find_by!(custom_id: "ITEM-0001")

    @inventory.update!(
      custom_id_config: [
        { "type" => "fixed", "value" => "PART-", "format" => "" },
        { "type" => "sequence", "value" => "", "format" => "D4" }
      ]
    )

    assert_equal "ITEM-0001", existing_item.reload.custom_id
    assert_not existing_item.update(custom_id: "ITEM-0001")
    assert existing_item.errors[:custom_id].any?
    assert existing_item.update(custom_id: "PART-0009")
  end

  test "caps custom ID elements at 10 and falls back to ITEM-0001 when empty" do
    twelve_elements = (1..12).map { |i| { "type" => "fixed", "value" => "E#{i}-", "format" => "" } }
    @inventory.update!(custom_id_config: twelve_elements)
    generated = CustomIdGenerator.new(@inventory).generate(preview: true)
    assert_includes generated, "E10-"
    assert_not_includes generated, "E11-"

    @inventory.update!(custom_id_config: [])
    assert_equal "ITEM-0001", CustomIdGenerator.new(@inventory).generate(preview: false)
  end

  test "exports inventory items to UTF-8 BOM CSV and valid Excel XLSX workbook" do
    @inventory.sync_custom_fields_params!([
      { field_type: "string", name: "Model", position: 1 },
      { field_type: "int", name: "Price", position: 2 },
      { field_type: "bool", name: "Verified", position: 3 }
    ])
    @inventory.save!
    by_name = @inventory.ordered_custom_fields.index_by(&:name)

    item = @inventory.items.build(created_by: @owner, custom_id: "ITEM-0001")
    item.assign_dynamic_field_values(
      by_name["Model"].id.to_s => "Oscilloscope \u{1F4E6}",
      by_name["Price"].id.to_s => "1250.5",
      by_name["Verified"].id.to_s => "1"
    )
    item.save!

    exporter = InventoryExporter.new(@inventory)

    csv_data = exporter.to_csv
    assert csv_data.start_with?(InventoryExporter::UTF8_BOM)
    rows = CSV.parse(csv_data.delete_prefix(InventoryExporter::UTF8_BOM), headers: true)
    assert_equal 1, rows.size
    assert_equal "ITEM-0001", rows.first["Custom ID"]
    assert_equal "Oscilloscope \u{1F4E6}", rows.first["Model"]
    assert_equal "1250.5", rows.first["Price"]

    xlsx_data = exporter.to_xlsx
    assert xlsx_data.bytesize > 500
    assert xlsx_data.b.start_with?("PK\x03\x04".b)

    multi_csv = InventoryExporter.inventories_to_csv([ @inventory ])
    assert multi_csv.start_with?(InventoryExporter::UTF8_BOM)
    assert_includes multi_csv, @inventory.title
  end
end
