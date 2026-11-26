# frozen_string_literal: true

require "application_system_test_case"

class InventoryHubE2eTest < ApplicationSystemTestCase
  setup do
    @category = Category.create!(name: "E2E Category #{SecureRandom.hex(4)}")
    @owner = User.create!(
      name: "E2E Owner",
      email: "e2e-owner-#{SecureRandom.hex(4)}@example.com",
      provider: "email",
      uid: "unconfirmed:e2e-owner-#{SecureRandom.hex(4)}",
      password: "Password123!"
    )
    @inventory = Inventory.create!(
      title: "Browser E2E Telemetry Lab",
      description: "End-to-end Selenium verification inventory",
      category: @category,
      creator: @owner,
      is_public: false
    )
  end

  test "switches locale between EN and ES and toggles dark theme in browser" do
    visit root_path
    assert_selector "html[lang='en']"
    assert_selector "html[data-bs-theme='light']"
    assert_text "Browser E2E Telemetry Lab"

    click_button "ES"
    assert_selector "html[lang='es']"

    click_button "EN"
    assert_selector "html[lang='en']"

    find("form[action*='preferences/theme'] button").click
    assert_selector "html[data-bs-theme='dark']"
  end

  test "enables toolbar actions on row checkbox selection and bulk deletes selected item" do
    item = @inventory.items.create!(created_by: @owner, custom_id: "ITEM-0001")
    sign_in_in_browser(@owner)

    visit inventory_path(@inventory, tab: "items")
    assert_text item.custom_id
    assert_selector "button[data-table-selection-target='singleAction'][disabled]"
    assert_selector "button[data-table-selection-target='bulkAction'][disabled]"

    find("input[data-table-selection-target='rowCheckbox'][value='#{item.id}']").check
    assert_no_selector "button[data-table-selection-target='singleAction'][disabled]"
    assert_no_selector "button[data-table-selection-target='bulkAction'][disabled]"

    accept_confirm do
      find("button[data-action='click->table-selection#submitBulk']").click
    end

    assert_no_text item.custom_id
    assert_equal 0, @inventory.reload.items_count
  end

  test "adds custom ID elements and adds and removes dynamic fields via Stimulus" do
    sign_in_in_browser(@owner)

    visit inventory_path(@inventory, tab: "custom_id")
    initial_parts = all("select.id-part-type", visible: true).size
    find("button[data-action='click->inventory-workspace#addIdElement']").click
    assert_selector "select.id-part-type", count: initial_parts + 1, visible: true

    visit inventory_path(@inventory, tab: "fields")
    initial_fields = all("select[data-action='change->inventory-workspace#onDynamicFieldTypeChange']", visible: true).size
    find("button[data-action='click->inventory-workspace#addDynamicField']").click
    assert_selector "select[data-action='change->inventory-workspace#onDynamicFieldTypeChange']", count: initial_fields + 1, visible: true

    all("button[data-action='click->inventory-workspace#removeDynamicField']", visible: true).last.click
    assert_selector "select[data-action='change->inventory-workspace#onDynamicFieldTypeChange']", count: initial_fields, visible: true
  end

  test "posts a live discussion comment from the browser" do
    sign_in_in_browser(@owner)

    visit inventory_path(@inventory, tab: "discussion")
    find("textarea[name='comment[body]']").set("Selenium E2E live check passed")
    find("form[action*='/comments'] button[type='submit'], form[action*='/comments'] input[type='submit']").click

    assert_text "Selenium E2E live check passed"
    assert_equal 1, @inventory.comments.reload.count
  end

  private

  def sign_in_in_browser(user)
    token = user.generate_token_for(:email_confirmation)
    visit confirm_email_path(token: token)
    assert_text user.name
  end
end
