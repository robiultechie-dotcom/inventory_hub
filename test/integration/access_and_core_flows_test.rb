# frozen_string_literal: true

require "test_helper"

class AccessAndCoreFlowsTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: "Integration Category #{SecureRandom.hex(4)}")
    @owner = User.create!(
      name: "Regular User",
      email: "regular-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:regular-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @admin = User.create!(
      name: "Admin User",
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:admin-#{SecureRandom.hex(4)}",
      password: "Password123!",
      admin: true
    )
    @inventory = Inventory.create!(
      title: "Server Rack Registry",
      description: "Data center hardware tracking",
      category: @category,
      creator: @owner,
      is_public: true
    )
  end

  test "guest can view health check, home page, inventory details, and search results" do
    get rails_health_check_path
    assert_response :success

    get root_path
    assert_response :success
    assert_includes response.body, "Server Rack Registry"

    get inventory_path(@inventory)
    assert_response :success

    get search_path, params: { q: "Server" }
    assert_response :success
    assert_includes response.body, "Server Rack Registry"
  end

  test "guest cannot create inventories or access admin panel" do
    assert_no_difference("Inventory.count") do
      post inventories_path, params: {
        inventory: {
          title: "Unauthorized Inventory",
          category_id: @category.id
        }
      }
    end
    assert_response :redirect

    get admin_users_path
    assert_response :redirect
  end

  test "confirmed standard user can sign in, create inventory, and is blocked from admin panel" do
    sign_in_via_confirmation(@owner)

    get admin_users_path
    assert_response :redirect

    assert_difference("Inventory.count", 1) do
      post inventories_path, params: {
        inventory: {
          title: "User Created Inventory",
          description: "Created during integration test",
          category_id: @category.id,
          is_public: false
        }
      }
    end
    assert_response :redirect
  end

  test "admin user can access admin panel and export inventory items CSV" do
    @inventory.items.create!(created_by: @owner)
    sign_in_via_confirmation(@admin)

    get admin_users_path
    assert_response :success

    get export_items_csv_inventory_path(@inventory)
    assert_response :success
    assert_includes response.media_type, "csv"
  end

  private

  def sign_in_via_confirmation(user)
    token = user.generate_token_for(:email_confirmation)
    get confirm_email_path(token: token)
    assert_response :redirect
  end
end
