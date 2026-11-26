# frozen_string_literal: true

require "test_helper"

class CustomFieldsAndRegressionTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(name: "Audit Category #{SecureRandom.hex(4)}")
    @owner = User.create!(
      name: "Field Owner",
      email: "field-owner-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "confirmed:owner-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @inventory = Inventory.create!(
      title: "Engineering Hardware Registry",
      description: "Test inventory for dynamic fields and aggregations",
      category: @category,
      creator: @owner
    )
  end

  test "supports unlimited custom fields beyond 3 per type" do
    entries = (1..5).map do |i|
      {
        field_type: "string",
        name: "Spec #{i}",
        description: "Specification #{i}",
        show_in_table: true,
        position: i
      }
    end

    @inventory.sync_custom_fields_params!(entries)
    @inventory.save!
    @inventory.reload

    assert_equal 5, @inventory.ordered_custom_fields.size
    fields = @inventory.ordered_custom_fields

    item = @inventory.items.build(created_by: @owner)
    item.assign_dynamic_field_values(fields.each_with_object({}) { |f, h| h[f.id.to_s] = "Val-#{f.position}" })
    assert item.save

    item.reload
    fields.each do |field|
      assert_equal "Val-#{field.position}", item.value_for(field)
    end
  end

  test "enforces tuning rules for string regex, length bounds, numeric range, select list, and URLs" do
    @inventory.sync_custom_fields_params!([
      { field_type: "string", name: "SKU", min_length: 4, max_length: 10, regex_pattern: "\\A[A-Z]{2}-\\d+\\z", position: 1 },
      { field_type: "int", name: "Price", min_value: 10, max_value: 500, position: 2 },
      { field_type: "select", name: "Type", select_options: "Desktop, Laptop, Table", position: 3 },
      { field_type: "link", name: "Datasheet", position: 4 }
    ])
    @inventory.save!

    by_name = @inventory.ordered_custom_fields.index_by(&:name)

    bad_item = @inventory.items.build(created_by: @owner)
    bad_item.assign_dynamic_field_values(
      by_name["SKU"].id.to_s => "ab",
      by_name["Price"].id.to_s => "999",
      by_name["Type"].id.to_s => "InvalidOption",
      by_name["Datasheet"].id.to_s => "not-a-url"
    )
    assert_not bad_item.valid?
    error_text = bad_item.errors.full_messages.join(" | ")
    assert_includes error_text, "SKU"
    assert_includes error_text, "Price"
    assert_includes error_text, "Type"
    assert_includes error_text, "Datasheet"

    good_item = @inventory.items.build(created_by: @owner)
    good_item.assign_dynamic_field_values(
      by_name["SKU"].id.to_s => "AB-1234",
      by_name["Price"].id.to_s => "250.5",
      by_name["Type"].id.to_s => "Laptop",
      by_name["Datasheet"].id.to_s => "https://example.com/spec.pdf"
    )
    assert good_item.save
    assert_equal "Laptop", good_item.reload.value_for(by_name["Type"])
  end

  test "rejects invalid custom field definitions such as min greater than max or broken regex" do
    bad_range = @inventory.custom_fields.build(field_type: "int", name: "Bad Range", min_value: 100, max_value: 10)
    assert_not bad_range.valid?
    assert bad_range.errors[:min_value].any?

    bad_regex = @inventory.custom_fields.build(field_type: "string", name: "Bad Regex", regex_pattern: "[unclosed")
    assert_not bad_regex.valid?
    assert bad_regex.errors[:regex_pattern].any?

    empty_select = @inventory.custom_fields.build(field_type: "select", name: "Empty Select", select_options: "   ")
    assert_not empty_select.valid?
    assert empty_select.errors[:select_options].any?
  end

  test "deleting a legacy-backed field and adding a new field never leaks phantom values or ghost search hits" do
    old_field = @inventory.custom_fields.create!(
      field_type: "string",
      name: "Model",
      legacy_slot_key: "string1",
      position: 1
    )

    item = @inventory.items.create!(created_by: @owner, custom_string1_val: "PhantomMacBook99")
    assert_equal "PhantomMacBook99", item.reload.value_for(old_field)
    assert_includes Item.full_text_search("PhantomMacBook99"), item

    @inventory.reload
    @inventory.sync_custom_fields_params!([
      { field_type: "string", name: "Serial Number", show_in_table: true, position: 1 }
    ])
    @inventory.save!

    new_field = @inventory.reload.ordered_custom_fields.first
    assert_equal "Serial Number", new_field.name
    assert_nil new_field.legacy_slot_key

    item.reload
    assert_nil item.custom_string1_val
    assert_nil item.value_for(new_field)
    assert_not_includes Item.full_text_search("PhantomMacBook99"), item
  end

  test "computes batched SQL statistics for numeric, string, and select fields" do
    @inventory.sync_custom_fields_params!([
      { field_type: "int", name: "Cost", position: 1 },
      { field_type: "string", name: "Brand", position: 2 },
      { field_type: "select", name: "Status", select_options: "Active, Spare", position: 3 }
    ])
    @inventory.save!
    by_name = @inventory.ordered_custom_fields.index_by(&:name)

    [
      { cost: "100", brand: "Dell", status: "Active" },
      { cost: "200", brand: "Dell", status: "Active" },
      { cost: "300", brand: "HP", status: "Spare" }
    ].each do |row|
      item = @inventory.items.build(created_by: @owner)
      item.assign_dynamic_field_values(
        by_name["Cost"].id.to_s => row[:cost],
        by_name["Brand"].id.to_s => row[:brand],
        by_name["Status"].id.to_s => row[:status]
      )
      item.save!
    end

    @inventory.items.first.likes.create!(user: @owner)
    stats = @inventory.reload.statistics

    assert_equal 3, stats[:total_items]
    assert_equal 1, stats[:total_likes]

    cost_stat = stats[:numeric].find { |s| s[:name] == "Cost" }
    assert_equal 200.0, cost_stat[:avg]
    assert_equal BigDecimal("100"), cost_stat[:min]
    assert_equal BigDecimal("300"), cost_stat[:max]

    brand_stat = stats[:strings].find { |s| s[:name] == "Brand" }
    assert_equal [ "Dell", 2 ], brand_stat[:top_values].first

    status_stat = stats[:strings].find { |s| s[:name] == "Status" }
    assert_equal [ "Active", 2 ], status_stat[:top_values].first
  end

  test "allows identical custom_id in different inventories and enforces one like per user per item" do
    other_inventory = Inventory.create!(
      title: "Second Registry",
      category: @category,
      creator: @owner
    )

    first_item = @inventory.items.create!(created_by: @owner, custom_id: "ITEM-0042")
    second_item = other_inventory.items.create!(created_by: @owner, custom_id: "ITEM-0042")
    assert_equal first_item.custom_id, second_item.custom_id

    first_item.likes.create!(user: @owner)
    duplicate_like = first_item.likes.build(user: @owner)
    assert_not duplicate_like.valid?
    assert_equal 1, first_item.reload.likes_count
  end

  test "invalidates email confirmation token after account is confirmed" do
    unconfirmed = User.create!(
      name: "Pending User",
      email: "  PENDING-#{SecureRandom.hex(4)}@Example.COM ",
      provider: "email",
      uid: "unconfirmed:#{SecureRandom.hex(8)}",
      password: "Password123!"
    )

    assert unconfirmed.email_unconfirmed?
    assert unconfirmed.valid_password?("Password123!")
    assert_not unconfirmed.valid_password?("WrongPassword")

    token = unconfirmed.generate_token_for(:email_confirmation)
    assert_equal unconfirmed, User.find_by_token_for(:email_confirmation, token)

    unconfirmed.confirm_email!
    assert_not unconfirmed.email_unconfirmed?
    assert_nil User.find_by_token_for(:email_confirmation, token)
  end
end
