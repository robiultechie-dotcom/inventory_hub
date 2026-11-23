# frozen_string_literal: true

class InitSchema < ActiveRecord::Migration[8.0]
  def up
    enable_extension "plpgsql" unless extension_enabled?("plpgsql")

    unless table_exists?(:users)
      create_table :users do |t|
        t.string  :name, null: false
        t.string  :email, default: "", null: false
        t.string  :encrypted_password, default: "", null: false
        t.string  :provider
        t.string  :uid
        t.string  :avatar_url
        t.boolean :admin, default: false, null: false
        t.boolean :blocked, default: false, null: false
        t.string  :locale, default: "en", null: false
        t.string  :theme, default: "light", null: false
        t.timestamps

        t.index :email, unique: true
        t.index [ :provider, :uid ], unique: true
      end
    end

    unless table_exists?(:categories)
      create_table :categories do |t|
        t.string :name, null: false
        t.timestamps

        t.index :name, unique: true
      end
    end

    unless table_exists?(:inventories)
      create_table :inventories do |t|
        t.string  :title, null: false
        t.text    :description
        t.string  :image_url
        t.bigint  :creator_id, null: false
        t.bigint  :category_id, null: false
        t.boolean :is_public, default: false, null: false
        t.integer :items_count, default: 0, null: false
        t.integer :lock_version, default: 0, null: false
        t.jsonb   :custom_id_config, default: [], null: false

        %w[string text int link bool].each do |type|
          (1..3).each do |i|
            t.boolean "custom_#{type}#{i}_state", default: false, null: false
            t.string  "custom_#{type}#{i}_name"
            t.string  "custom_#{type}#{i}_desc"
            t.boolean "custom_#{type}#{i}_show_in_table", default: (i == 1), null: false
            t.integer "custom_#{type}#{i}_position", default: i, null: false
          end
        end

        t.timestamps

        t.index :category_id
        t.index :creator_id
        t.index :created_at
        t.index :items_count
      end
    end

    unless table_exists?(:items)
      create_table :items do |t|
        t.bigint  :inventory_id, null: false
        t.bigint  :created_by_id, null: false
        t.string  :custom_id, null: false
        t.integer :likes_count, default: 0, null: false
        t.integer :lock_version, default: 0, null: false

        (1..3).each do |i|
          t.string  "custom_string#{i}_val"
          t.text    "custom_text#{i}_val"
          t.decimal "custom_int#{i}_val", precision: 15, scale: 4
          t.string  "custom_link#{i}_val"
          t.boolean "custom_bool#{i}_val", default: false, null: false
        end

        t.timestamps

        t.index :created_by_id
        t.index [ :inventory_id, :custom_id ], unique: true
        t.index :inventory_id
      end
    end

    unless table_exists?(:tags)
      create_table :tags do |t|
        t.string  :name, null: false
        t.integer :inventories_count, default: 0, null: false
        t.timestamps

        t.index :name, unique: true
      end
    end

    unless table_exists?(:inventory_tags)
      create_table :inventory_tags do |t|
        t.bigint :inventory_id, null: false
        t.bigint :tag_id, null: false
        t.timestamps

        t.index [ :inventory_id, :tag_id ], unique: true
        t.index :tag_id
      end
    end

    unless table_exists?(:inventory_accesses)
      create_table :inventory_accesses do |t|
        t.bigint :inventory_id, null: false
        t.bigint :user_id, null: false
        t.timestamps

        t.index [ :inventory_id, :user_id ], unique: true
        t.index :user_id
      end
    end

    unless table_exists?(:comments)
      create_table :comments do |t|
        t.bigint :inventory_id, null: false
        t.bigint :user_id, null: false
        t.text   :body, null: false
        t.timestamps

        t.index [ :inventory_id, :created_at ]
        t.index :user_id
      end
    end

    unless table_exists?(:likes)
      create_table :likes do |t|
        t.bigint :item_id, null: false
        t.bigint :user_id, null: false
        t.timestamps

        t.index [ :item_id, :user_id ], unique: true
        t.index :user_id
      end
    end

    add_foreign_key :comments, :inventories, on_delete: :cascade unless foreign_key_exists?(:comments, :inventories)
    add_foreign_key :comments, :users, on_delete: :cascade unless foreign_key_exists?(:comments, :users)
    add_foreign_key :inventories, :categories unless foreign_key_exists?(:inventories, :categories)
    add_foreign_key :inventories, :users, column: :creator_id, on_delete: :cascade unless foreign_key_exists?(:inventories, :users, column: :creator_id)
    add_foreign_key :inventory_accesses, :inventories, on_delete: :cascade unless foreign_key_exists?(:inventory_accesses, :inventories)
    add_foreign_key :inventory_accesses, :users, on_delete: :cascade unless foreign_key_exists?(:inventory_accesses, :users)
    add_foreign_key :inventory_tags, :inventories, on_delete: :cascade unless foreign_key_exists?(:inventory_tags, :inventories)
    add_foreign_key :inventory_tags, :tags, on_delete: :cascade unless foreign_key_exists?(:inventory_tags, :tags)
    add_foreign_key :items, :inventories, on_delete: :cascade unless foreign_key_exists?(:items, :inventories)
    add_foreign_key :items, :users, column: :created_by_id, on_delete: :cascade unless foreign_key_exists?(:items, :users, column: :created_by_id)
    add_foreign_key :likes, :items, on_delete: :cascade unless foreign_key_exists?(:likes, :items)
    add_foreign_key :likes, :users, on_delete: :cascade unless foreign_key_exists?(:likes, :users)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Baseline schema migration cannot be rolled back."
  end
end
