# frozen_string_literal: true

require "test_helper"

class InventoryAndItemWorkflowsTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: "Workflow Category #{SecureRandom.hex(4)}")
    @owner = User.create!(
      name: "Workflow Owner",
      email: "wf-owner-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:wf-owner-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @other = User.create!(
      name: "Collaborator User",
      email: "wf-collab-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:wf-collab-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @inventory = Inventory.create!(
      title: "Private Optics Lab",
      description: "Restricted optical instruments",
      category: @category,
      creator: @owner,
      is_public: false
    )
  end

  test "enforces optimistic locking and force overwrite on inventory settings, custom ID, and dynamic fields JSON" do
    sign_in_via_confirmation(@owner)
    stale_version = @inventory.lock_version

    patch inventory_path(@inventory),
          params: { inventory: { title: "Updated Optics Lab", lock_version: stale_version } },
          as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "saved", body["status"]
    assert_equal stale_version + 1, body["lock_version"]

    patch inventory_path(@inventory),
          params: { inventory: { title: "Conflicting Update", lock_version: stale_version } },
          as: :json
    assert_response :conflict
    conflict_body = JSON.parse(response.body)
    assert_equal "conflict", conflict_body["status"]

    patch inventory_path(@inventory),
          params: { force_overwrite: "1", inventory: { title: "Forced Optics Lab", lock_version: stale_version } },
          as: :json
    assert_response :success
    assert_equal "Forced Optics Lab", @inventory.reload.title

    patch update_custom_id_inventory_path(@inventory),
          params: {
            lock_version: @inventory.reload.lock_version,
            elements: [
              { type: "fixed", spec: "OPT-" },
              { type: "sequence", spec: "D4" }
            ]
          },
          as: :json
    assert_response :success
    assert_equal "OPT-0001", JSON.parse(response.body)["id_preview"]

    patch update_fields_inventory_path(@inventory),
          params: {
            lock_version: @inventory.reload.lock_version,
            custom_fields_submitted: "1",
            custom_fields: [
              { field_type: "string", name: "Manufacturer", show_in_table: "1", position: 1 },
              { field_type: "int", name: "Power", min_value: 1, max_value: 500, show_in_table: "1", position: 2 }
            ]
          },
          as: :json
    assert_response :success
    fields_body = JSON.parse(response.body)
    assert_equal 2, fields_body["active_fields_count"]

    patch update_fields_inventory_path(@inventory),
          params: { lock_version: 0, custom_fields_submitted: "1", custom_fields: [] },
          as: :json
    assert_response :conflict
  end

  test "enforces write access grant and revoke flow for restricted inventory items" do
    sign_in_via_confirmation(@other)

    get inventory_path(@inventory, tab: "settings")
    assert_response :success
    assert_not_includes response.body, "Save Changes"

    patch inventory_path(@inventory),
          params: { inventory: { title: "Hijacked Title" } },
          as: :json
    assert_response :forbidden

    assert_no_difference("Item.count") do
      post inventory_items_path(@inventory), params: { item: { custom_id: "ITEM-0001" } }
    end
    assert_response :redirect

    delete sign_out_path
    sign_in_via_confirmation(@owner)

    post grant_access_inventory_path(@inventory), params: { user_identifier: @other.email }
    assert_response :redirect
    assert @inventory.reload.writable_by?(@other)

    access_record = @inventory.inventory_accesses.find_by!(user: @other)
    delete revoke_access_inventory_path(@inventory), params: { ids: [ access_record.id ] }
    assert_response :redirect
    assert_not @inventory.reload.writable_by?(@other)
  end

  test "creates items with dynamic field values, enforces item optimistic locking, toggles likes, and bulk destroys" do
    @inventory.sync_custom_fields_params!([
      { field_type: "string", name: "Model", show_in_table: true, position: 1 }
    ])
    @inventory.save!
    model_field = @inventory.ordered_custom_fields.first

    sign_in_via_confirmation(@owner)

    assert_difference("Item.count", 1) do
      post inventory_items_path(@inventory), params: {
        item: { custom_id: "ITEM-0010" },
        field_values: { model_field.id.to_s => "Zeiss Pro" }
      }
    end
    assert_response :redirect

    item = @inventory.items.find_by!(custom_id: "ITEM-0010")
    assert_equal "Zeiss Pro", item.value_for(model_field)

    stale_version = item.lock_version
    item.update!(custom_id: "ITEM-0011")

    patch inventory_item_path(@inventory, item), params: {
      item: { custom_id: "ITEM-0012", lock_version: stale_version }
    }
    assert_response :conflict

    patch inventory_item_path(@inventory, item), params: {
      force_overwrite: "1",
      item: { custom_id: "ITEM-0012", lock_version: stale_version }
    }
    assert_response :redirect
    assert_equal "ITEM-0012", item.reload.custom_id

    post toggle_like_inventory_item_path(@inventory, item), as: :json
    assert_response :success
    like_json = JSON.parse(response.body)
    assert_equal true, like_json["liked"]
    assert_equal 1, like_json["likes_count"]

    post toggle_like_inventory_item_path(@inventory, item), as: :json
    assert_response :success
    unlike_json = JSON.parse(response.body)
    assert_equal false, unlike_json["liked"]
    assert_equal 0, unlike_json["likes_count"]

    delete bulk_destroy_inventory_items_path(@inventory), params: { ids: [ item.id ] }
    assert_response :redirect
    assert_equal 0, @inventory.reload.items_count
  end

  test "prevents standard user from bulk destroying another users inventory and supports XLSX and stats" do
    other_inventory = Inventory.create!(
      title: "Other User Inventory",
      category: @category,
      creator: @other
    )
    @inventory.items.create!(created_by: @owner)

    sign_in_via_confirmation(@owner)

    assert_no_difference("Inventory.count") do
      delete bulk_destroy_inventories_path, params: { ids: [ other_inventory.id ] }
    end
    assert Inventory.exists?(other_inventory.id)

    get inventory_path(@inventory, tab: "stats")
    assert_response :success

    get export_items_xlsx_inventory_path(@inventory)
    assert_response :success
    assert response.body.b.start_with?("PK\x03\x04".b)

    get export_csv_inventories_path, params: { ids: [ @inventory.id ] }
    assert_response :success
    assert_includes response.body, @inventory.title
  end

  private

  def sign_in_via_confirmation(user)
    token = user.generate_token_for(:email_confirmation)
    get confirm_email_path(token: token)
    assert_response :redirect
    follow_redirect!
  end
end
