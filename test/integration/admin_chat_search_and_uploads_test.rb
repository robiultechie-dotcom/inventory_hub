# frozen_string_literal: true

require "test_helper"
require "digest/sha1"

class AdminChatSearchAndUploadsTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: "Platform Category #{SecureRandom.hex(4)}")
    @admin = User.create!(
      name: "Platform Admin",
      email: "platform-admin-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:admin-#{SecureRandom.hex(4)}",
      password: "Password123!",
      admin: true
    )
    @member = User.create!(
      name: "UniqueSearchMember",
      email: "member-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:member-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @blocked_user = User.create!(
      name: "UniqueSearchBlocked",
      email: "blocked-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "confirmed:blocked-#{SecureRandom.hex(4)}",
      password: "Password123!",
      blocked: true
    )
    @inventory = Inventory.create!(
      title: "Laser Telemetry Vault",
      description: "High accuracy optical telemetry sensors",
      category: @category,
      creator: @member,
      is_public: false,
      tag_list: "optics, laser"
    )
  end

  test "admin can block, unblock, promote, and self-demote with immediate privilege loss" do
    sign_in_via_confirmation(@admin)

    post bulk_action_admin_users_path, params: { operation: "block", ids: [ @member.id ] }
    assert_response :redirect
    assert @member.reload.blocked?

    post bulk_action_admin_users_path, params: { operation: "unblock", ids: [ @member.id ] }
    assert_response :redirect
    assert_not @member.reload.blocked?

    post bulk_action_admin_users_path, params: { operation: "make_admin", ids: [ @member.id ] }
    assert_response :redirect
    assert @member.reload.admin?

    post bulk_action_admin_users_path, params: { operation: "remove_admin", ids: [ @admin.id ] }
    assert_redirected_to root_path
    assert_not @admin.reload.admin?

    get admin_users_path
    assert_redirected_to root_path
  end

  test "blocked user session is immediately invalidated on next request" do
    sign_in_via_confirmation(@member)
    @member.update!(blocked: true)

    assert_no_difference("Inventory.count") do
      post inventories_path, params: {
        inventory: { title: "Blocked Attempt", category_id: @category.id }
      }
    end
    assert_redirected_to root_path
  end

  test "supports live comments XHR creation, guest rejection, and ETag 304 polling" do
    post inventory_comments_path(@inventory),
         params: { comment: { body: "Guest attempt" } },
         xhr: true
    assert_response :unauthorized

    sign_in_via_confirmation(@member)

    assert_difference("Comment.count", 1) do
      post inventory_comments_path(@inventory),
           params: { comment: { body: "Calibration **passed**" } },
           xhr: true
    end
    assert_response :created
    assert_equal "1", response.headers["X-Comments-Count"]
    assert_includes response.body, "Calibration"

    get inventory_comments_path(@inventory)
    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?
    assert_equal "1", response.headers["X-Comments-Count"]

    get inventory_comments_path(@inventory), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "returns search suggestions with permission-aware item URLs and tag filtering" do
    item = @inventory.items.create!(created_by: @member, custom_string1_val: "SpectrometerX")

    get search_path, params: { tag: "optics" }
    assert_response :success
    assert_includes response.body, "Laser Telemetry Vault"

    get search_suggestions_path, params: { q: "SpectrometerX" }
    assert_response :success
    guest_json = JSON.parse(response.body)
    assert_equal inventory_item_path(@inventory, item), guest_json["items"].first["url"]

    sign_in_via_confirmation(@member)

    get search_suggestions_path, params: { q: "SpectrometerX" }
    assert_response :success
    owner_json = JSON.parse(response.body)
    assert_equal edit_inventory_item_path(@inventory, item), owner_json["items"].first["url"]
  end

  test "enforces user autocomplete minimum length, excludes blocked users, and filters workspace" do
    get autocomplete_users_path, params: { q: "Unique" }, as: :json
    assert_response :unauthorized

    sign_in_via_confirmation(@member)

    get autocomplete_users_path, params: { q: "U" }, as: :json
    assert_response :success
    assert_equal [], JSON.parse(response.body)

    get autocomplete_users_path, params: { q: "UniqueSearch" }, as: :json
    assert_response :success
    names = JSON.parse(response.body).map { |u| u["name"] }
    assert_includes names, "UniqueSearchMember"
    assert_not_includes names, "UniqueSearchBlocked"

    get user_path(@member), params: { owned_q: "Laser", owned_sort: "title_asc", access_sort: "most_items" }
    assert_response :success
    assert_includes response.body, "Laser Telemetry Vault"
  end

  test "generates valid SHA-1 Cloudinary upload signature and rejects unconfigured server" do
    post upload_signature_path, as: :json
    assert_response :unauthorized

    sign_in_via_confirmation(@member)
    original_url = ENV["CLOUDINARY_URL"]

    begin
      ENV["CLOUDINARY_URL"] = ""
      post upload_signature_path, as: :json
      assert_response :unprocessable_entity

      ENV["CLOUDINARY_URL"] = "cloudinary://demo_key:demo_secret@demo_cloud"
      post upload_signature_path, as: :json
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]

      payload = JSON.parse(response.body)
      assert_equal "demo_cloud", payload["cloud_name"]
      assert_equal "demo_key", payload["api_key"]
      expected_sig = Digest::SHA1.hexdigest("timestamp=#{payload["timestamp"]}demo_secret")
      assert_equal expected_sig, payload["signature"]
    ensure
      ENV["CLOUDINARY_URL"] = original_url
    end
  end

  private

  def sign_in_via_confirmation(user)
    token = user.generate_token_for(:email_confirmation)
    get confirm_email_path(token: token)
    assert_response :redirect
    follow_redirect!
  end
end
