# frozen_string_literal: true

require "bcrypt"
require "yaml"

seed_path = Rails.root.join("db/seeds/demo_data.yml")
data = YAML.safe_load_file(seed_path, permitted_classes: [], aliases: true)

puts "==> Seeding InventoryHub database from db/seeds/demo_data.yml..."

ActiveRecord::Base.transaction do
  categories = data.fetch("categories").index_with do |name|
    Category.find_or_create_by!(name: name)
  end

  default_pw = BCrypt::Password.create("password123")
  users = data.fetch("users").each_with_object({}) do |spec, acc|
    user = User.find_or_initialize_by(email: spec.fetch("email"))
    if user.new_record?
      user.assign_attributes(
        name:               spec.fetch("name"),
        admin:              spec.fetch("admin"),
        blocked:            false,
        provider:           spec.fetch("provider"),
        uid:                "oauth-#{spec.fetch('email')}",
        encrypted_password: default_pw
      )
      user.save!
    end
    acc[spec.fetch("key")] = user
  end

  data.fetch("inventories").each do |spec|
    inv = Inventory.find_or_initialize_by(title: spec.fetch("title"))
    was_new = inv.new_record?

    if was_new
      inv.assign_attributes(
        creator:          users.fetch(spec.fetch("creator")),
        category:         categories.fetch(spec.fetch("category")),
        description:      spec.fetch("description"),
        image_url:        spec.fetch("image_url"),
        is_public:        spec.fetch("is_public"),
        custom_id_config: spec.fetch("custom_id_config"),
        **spec.fetch("fields").transform_keys(&:to_sym)
      )
      inv.tag_list = spec.fetch("tags").join(", ")
      inv.save!
      ts = spec.fetch("days_ago").days.ago
      inv.update_columns(created_at: ts, updated_at: ts)
    elsif inv.tags.none?
      inv.update!(tag_list: spec.fetch("tags").join(", "))
    end

    spec.fetch("items").each do |item_spec|
      item = inv.items.find_or_initialize_by(custom_id: item_spec.fetch("custom_id"))
      next unless item.new_record?

      item.assign_attributes(
        created_by:         users.fetch(item_spec.fetch("creator")),
        custom_string1_val: item_spec["string1"],
        custom_int1_val:    item_spec["int1"],
        custom_int2_val:    item_spec["int2"],
        custom_link1_val:   item_spec["link1"]
      )
      item.save!
      item_ts = item_spec["hours_ago"] ? item_spec["hours_ago"].hours.ago : item_spec.fetch("days_ago").days.ago
      item.update_columns(created_at: item_ts, updated_at: item_ts)
    end
  end

  Inventory.find_each { |inv| Inventory.reset_counters(inv.id, :items) }
  Tag.find_each       { |tag| Tag.reset_counters(tag.id, :inventory_tags) }

  if ENV["ADMIN_EMAIL"].present?
    admin_user = User.find_by("LOWER(email) = ?", ENV["ADMIN_EMAIL"].strip.downcase)
    admin_user&.update_columns(admin: true, blocked: false)
  end

  active_tags = Tag.joins(:inventory_tags).distinct.count
  raise "Seed integrity error: expected >= 4 categories, got #{Category.count}"   if Category.count < 4
  raise "Seed integrity error: expected >= 6 inventories, got #{Inventory.count}" if Inventory.count < 6
  raise "Seed integrity error: expected >= 21 items, got #{Item.count}"           if Item.count < 21
  raise "Seed integrity error: expected >= 12 active tags, got #{active_tags}"    if active_tags < 12

  puts "==> Seed verified! Categories: #{Category.count}, Inventories: #{Inventory.count}, Items: #{Item.count}, Active Tags: #{active_tags}"
end
