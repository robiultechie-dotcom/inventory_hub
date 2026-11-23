# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_23_080350) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, COALESCE(body, ''::text))", name: "index_comments_on_fts_vector", using: :gin
    t.index ["inventory_id", "created_at"], name: "index_comments_on_inventory_id_and_created_at"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "custom_fields", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.string "field_type", null: false
    t.string "name", null: false
    t.string "description", default: "", null: false
    t.boolean "show_in_table", default: true, null: false
    t.integer "position", default: 1, null: false
    t.integer "min_length"
    t.integer "max_length"
    t.string "regex_pattern"
    t.decimal "min_value", precision: 15, scale: 4
    t.decimal "max_value", precision: 15, scale: 4
    t.text "select_options"
    t.string "legacy_slot_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "field_type"], name: "index_custom_fields_on_inventory_id_and_field_type"
    t.index ["inventory_id", "position"], name: "index_custom_fields_on_inventory_id_and_position"
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
    t.boolean "custom_string1_state", default: false, null: false
    t.string "custom_string1_name"
    t.string "custom_string1_desc"
    t.boolean "custom_string1_show_in_table", default: true, null: false
    t.integer "custom_string1_position", default: 1, null: false
    t.boolean "custom_string2_state", default: false, null: false
    t.string "custom_string2_name"
    t.string "custom_string2_desc"
    t.boolean "custom_string2_show_in_table", default: false, null: false
    t.integer "custom_string2_position", default: 2, null: false
    t.boolean "custom_string3_state", default: false, null: false
    t.string "custom_string3_name"
    t.string "custom_string3_desc"
    t.boolean "custom_string3_show_in_table", default: false, null: false
    t.integer "custom_string3_position", default: 3, null: false
    t.boolean "custom_text1_state", default: false, null: false
    t.string "custom_text1_name"
    t.string "custom_text1_desc"
    t.boolean "custom_text1_show_in_table", default: true, null: false
    t.integer "custom_text1_position", default: 1, null: false
    t.boolean "custom_text2_state", default: false, null: false
    t.string "custom_text2_name"
    t.string "custom_text2_desc"
    t.boolean "custom_text2_show_in_table", default: false, null: false
    t.integer "custom_text2_position", default: 2, null: false
    t.boolean "custom_text3_state", default: false, null: false
    t.string "custom_text3_name"
    t.string "custom_text3_desc"
    t.boolean "custom_text3_show_in_table", default: false, null: false
    t.integer "custom_text3_position", default: 3, null: false
    t.boolean "custom_int1_state", default: false, null: false
    t.string "custom_int1_name"
    t.string "custom_int1_desc"
    t.boolean "custom_int1_show_in_table", default: true, null: false
    t.integer "custom_int1_position", default: 1, null: false
    t.boolean "custom_int2_state", default: false, null: false
    t.string "custom_int2_name"
    t.string "custom_int2_desc"
    t.boolean "custom_int2_show_in_table", default: false, null: false
    t.integer "custom_int2_position", default: 2, null: false
    t.boolean "custom_int3_state", default: false, null: false
    t.string "custom_int3_name"
    t.string "custom_int3_desc"
    t.boolean "custom_int3_show_in_table", default: false, null: false
    t.integer "custom_int3_position", default: 3, null: false
    t.boolean "custom_link1_state", default: false, null: false
    t.string "custom_link1_name"
    t.string "custom_link1_desc"
    t.boolean "custom_link1_show_in_table", default: true, null: false
    t.integer "custom_link1_position", default: 1, null: false
    t.boolean "custom_link2_state", default: false, null: false
    t.string "custom_link2_name"
    t.string "custom_link2_desc"
    t.boolean "custom_link2_show_in_table", default: false, null: false
    t.integer "custom_link2_position", default: 2, null: false
    t.boolean "custom_link3_state", default: false, null: false
    t.string "custom_link3_name"
    t.string "custom_link3_desc"
    t.boolean "custom_link3_show_in_table", default: false, null: false
    t.integer "custom_link3_position", default: 3, null: false
    t.boolean "custom_bool1_state", default: false, null: false
    t.string "custom_bool1_name"
    t.string "custom_bool1_desc"
    t.boolean "custom_bool1_show_in_table", default: true, null: false
    t.integer "custom_bool1_position", default: 1, null: false
    t.boolean "custom_bool2_state", default: false, null: false
    t.string "custom_bool2_name"
    t.string "custom_bool2_desc"
    t.boolean "custom_bool2_show_in_table", default: false, null: false
    t.integer "custom_bool2_position", default: 2, null: false
    t.boolean "custom_bool3_state", default: false, null: false
    t.string "custom_bool3_name"
    t.string "custom_bool3_desc"
    t.boolean "custom_bool3_show_in_table", default: false, null: false
    t.integer "custom_bool3_position", default: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))", name: "index_inventories_on_fts_vector", using: :gin
    t.index ["category_id"], name: "index_inventories_on_category_id"
    t.index ["created_at"], name: "index_inventories_on_created_at"
    t.index ["creator_id"], name: "index_inventories_on_creator_id"
    t.index ["items_count"], name: "index_inventories_on_items_count"
  end

  create_table "inventory_accesses", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "user_id"], name: "index_inventory_accesses_on_inventory_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_inventory_accesses_on_user_id"
  end

  create_table "inventory_tags", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id", "tag_id"], name: "index_inventory_tags_on_inventory_id_and_tag_id", unique: true
    t.index ["tag_id"], name: "index_inventory_tags_on_tag_id"
  end

  create_table "item_field_values", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.bigint "custom_field_id", null: false
    t.string "string_value"
    t.text "text_value"
    t.decimal "numeric_value", precision: 15, scale: 4
    t.boolean "boolean_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, (((COALESCE(string_value, ''::character varying))::text || ' '::text) || COALESCE(text_value, ''::text)))", name: "index_item_field_values_on_fts_vector", using: :gin
    t.index ["custom_field_id", "numeric_value"], name: "index_item_field_values_on_custom_field_id_and_numeric_value"
    t.index ["custom_field_id", "string_value"], name: "index_item_field_values_on_custom_field_id_and_string_value"
    t.index ["custom_field_id"], name: "index_item_field_values_on_custom_field_id"
    t.index ["item_id", "custom_field_id"], name: "index_item_field_values_on_item_id_and_custom_field_id", unique: true
  end

  create_table "items", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.bigint "created_by_id", null: false
    t.string "custom_id", null: false
    t.integer "likes_count", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "custom_string1_val"
    t.text "custom_text1_val"
    t.decimal "custom_int1_val", precision: 15, scale: 4
    t.string "custom_link1_val"
    t.boolean "custom_bool1_val", default: false, null: false
    t.string "custom_string2_val"
    t.text "custom_text2_val"
    t.decimal "custom_int2_val", precision: 15, scale: 4
    t.string "custom_link2_val"
    t.boolean "custom_bool2_val", default: false, null: false
    t.string "custom_string3_val"
    t.text "custom_text3_val"
    t.decimal "custom_int3_val", precision: 15, scale: 4
    t.string "custom_link3_val"
    t.boolean "custom_bool3_val", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, (((((((((((((COALESCE(custom_id, ''::character varying))::text || ' '::text) || (COALESCE(custom_string1_val, ''::character varying))::text) || ' '::text) || (COALESCE(custom_string2_val, ''::character varying))::text) || ' '::text) || (COALESCE(custom_string3_val, ''::character varying))::text) || ' '::text) || COALESCE(custom_text1_val, ''::text)) || ' '::text) || COALESCE(custom_text2_val, ''::text)) || ' '::text) || COALESCE(custom_text3_val, ''::text)))", name: "index_items_on_fts_vector", using: :gin
    t.index ["created_by_id"], name: "index_items_on_created_by_id"
    t.index ["inventory_id", "custom_id"], name: "index_items_on_inventory_id_and_custom_id", unique: true
    t.index ["inventory_id"], name: "index_items_on_inventory_id"
  end

  create_table "likes", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id", "user_id"], name: "index_likes_on_item_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.integer "inventories_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, (COALESCE(name, ''::character varying))::text)", name: "index_tags_on_fts_vector", using: :gin
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

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

  add_foreign_key "comments", "inventories", on_delete: :cascade
  add_foreign_key "comments", "users", on_delete: :cascade
  add_foreign_key "custom_fields", "inventories", on_delete: :cascade
  add_foreign_key "inventories", "categories"
  add_foreign_key "inventories", "users", column: "creator_id", on_delete: :cascade
  add_foreign_key "inventory_accesses", "inventories", on_delete: :cascade
  add_foreign_key "inventory_accesses", "users", on_delete: :cascade
  add_foreign_key "inventory_tags", "inventories", on_delete: :cascade
  add_foreign_key "inventory_tags", "tags", on_delete: :cascade
  add_foreign_key "item_field_values", "custom_fields", on_delete: :cascade
  add_foreign_key "item_field_values", "items", on_delete: :cascade
  add_foreign_key "items", "inventories", on_delete: :cascade
  add_foreign_key "items", "users", column: "created_by_id", on_delete: :cascade
  add_foreign_key "likes", "items", on_delete: :cascade
  add_foreign_key "likes", "users", on_delete: :cascade
end
