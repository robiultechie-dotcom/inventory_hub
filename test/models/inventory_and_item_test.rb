# frozen_string_literal: true

require "test_helper"

class InventoryAndItemTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(name: "Test Hardware #{SecureRandom.hex(4)}")
    @owner = User.create!(
      name: "Owner User",
      email: "owner-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "confirmed:owner-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @other = User.create!(
      name: "Other User",
      email: "other-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "confirmed:other-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @admin = User.create!(
      name: "Admin User",
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "confirmed:admin-#{SecureRandom.hex(4)}",
      password: "Password123!",
      admin: true
    )
    @inventory = Inventory.create!(
      title: "Oscilloscope Lab Assets",
      description: "Precision measurement equipment for electronics lab",
      category: @category,
      creator: @owner,
      is_public: false
    )
  end

  test "enforces manageable_by? and writable_by? access rules" do
    assert @inventory.manageable_by?(@owner)
    assert @inventory.manageable_by?(@admin)
    assert_not @inventory.manageable_by?(@other)
    assert_not @inventory.manageable_by?(nil)

    assert @inventory.writable_by?(@owner)
    assert @inventory.writable_by?(@admin)
    assert_not @inventory.writable_by?(@other)

    @inventory.inventory_accesses.create!(user: @other)
    assert @inventory.writable_by?(@other)

    public_inventory = Inventory.create!(
      title: "Shared Lab Inventory",
      category: @category,
      creator: @owner,
      is_public: true
    )
    assert public_inventory.writable_by?(@other)
    assert_not public_inventory.writable_by?(nil)
  end

  test "auto-generates sequential custom IDs and enforces format and uniqueness" do
    first_item = @inventory.items.create!(created_by: @owner)
    second_item = @inventory.items.create!(created_by: @owner)

    assert_match(/\AITEM-\d{4}\z/, first_item.custom_id)
    assert_match(/\AITEM-\d{4}\z/, second_item.custom_id)
    assert_not_equal first_item.custom_id, second_item.custom_id

    duplicate_item = @inventory.items.build(created_by: @owner, custom_id: first_item.custom_id)
    assert_not duplicate_item.valid?
    assert duplicate_item.errors[:custom_id].any?

    bad_format_item = @inventory.items.build(created_by: @owner, custom_id: "WRONG-FORMAT")
    assert_not bad_format_item.valid?
    assert bad_format_item.errors[:custom_id].any?
  end

  test "prevents lost updates on inventory via optimistic locking" do
    first_copy = Inventory.find(@inventory.id)
    second_copy = Inventory.find(@inventory.id)

    first_copy.update!(title: "Updated Oscilloscope Lab")

    assert_raises(ActiveRecord::StaleObjectError) do
      second_copy.update!(title: "Conflicting Lab Title")
    end
  end

  test "prevents lost updates on item via optimistic locking" do
    item = @inventory.items.create!(created_by: @owner)
    first_copy = Item.find(item.id)
    second_copy = Item.find(item.id)

    first_copy.update!(custom_string1_val: "Bench A")

    assert_raises(ActiveRecord::StaleObjectError) do
      second_copy.update!(custom_string1_val: "Bench B")
    end
  end

  test "PostgreSQL full_text_search finds matching inventories and items" do
    item = @inventory.items.create!(created_by: @owner, custom_string1_val: "Tektronix")

    assert_includes Inventory.full_text_search("Oscilloscope"), @inventory
    assert_not_includes Inventory.full_text_search("NonExistentKeywordXYZ"), @inventory

    assert_includes Item.full_text_search("Tektronix"), item
    assert_includes Item.full_text_search(item.custom_id), item
  end
end
