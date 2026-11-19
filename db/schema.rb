# frozen_string_literal: true

ActiveRecord::Schema[8.0].define(version: 2026_11_08_000001) do
  enable_extension "pg_catalog.plpgsql"

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "provider"
    t.string "uid"
    t.string "avatar_url"
    t.boolean "admin", default: false, null: false
    t.boolean "blocked", default: false, null: false
    t.string "locale", default: "en", null: false
    t.string "theme", default: "light", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "inventories", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.string "image_url"
    t.bigint "creator_id", null: false
    t.bigint "category_id", null: false
    t.boolean "is_public", default: false, null: false
    t.integer "items_count", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "custom_id_config", default: [], null: false

    # 15 Custom Field Definitions (3 per type: string, text, int, link, bool)
    %w[string text int link bool].each do |type|
      (1..3).each do |i|
        t.boolean "custom_#{type}#{i}_state", default: false, null: false
        t.string "custom_#{type}#{i}_name"
        t.string "custom_#{type}#{i}_desc"
        t.boolean "custom_#{type}#{i}_show_in_table", default: (i == 1), null: false
        t.integer "custom_#{type}#{i}_position", default: i, null: false
      end
    end

    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_inventories_on_category_id"
    t.index ["creator_id"], name: "index_inventories_on_creator_id"
    t.index ["created_at"], name: "index_inventories_on_created_at"
    t.index ["items_count"], name: "index_inventories_on_items_count"
  end

  create_table "items", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "created_by_id", null: false
    t.string "custom_id", null: false
    t.integer "likes_count", default: 0, null: false
    t.integer "lock_version", default: 0, null: false

    # 15 Custom Field Values matching Inventory Template
    (1..3).each do |i|
      t.string "custom_string#{i}_val"
      t.text "custom_text#{i}_val"
      t.decimal "custom_int#{i}_val", precision: 15, scale: 4
      t.string "custom_link#{i}_val"
      t.boolean "custom_bool#{i}_val", default: false, null: false
    end

    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_items_on_created_by_id"
    t.index ["inventory_id", "custom_id"], name: "index_items_on_inventory_id_and_custom_id", unique: true
    t.index ["inventory_id"], name: "index_items_on_inventory_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.integer "inventories_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "inventory_tags", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "tag_id"], name: "index_inventory_tags_on_inventory_id_and_tag_id", unique: true
    t.index ["tag_id"], name: "index_inventory_tags_on_tag_id"
  end

  create_table "inventory_accesses", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "user_id"], name: "index_inventory_accesses_on_inventory_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_inventory_accesses_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "created_at"], name: "index_comments_on_inventory_id_and_created_at"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "likes", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id", "user_id"], name: "index_likes_on_item_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  add_foreign_key "comments", "inventories", on_delete: :cascade
  add_foreign_key "comments", "users", on_delete: :cascade
  add_foreign_key "inventories", "categories"
  add_foreign_key "inventories", "users", column: "creator_id", on_delete: :cascade
  add_foreign_key "inventory_accesses", "inventories", on_delete: :cascade
  add_foreign_key "inventory_accesses", "users", on_delete: :cascade
  add_foreign_key "inventory_tags", "inventories", on_delete: :cascade
  add_foreign_key "inventory_tags", "tags", on_delete: :cascade
  add_foreign_key "items", "inventories", on_delete: :cascade
  add_foreign_key "items", "users", column: "created_by_id", on_delete: :cascade
  add_foreign_key "likes", "items", on_delete: :cascade
  add_foreign_key "likes", "users", on_delete: :cascade
end