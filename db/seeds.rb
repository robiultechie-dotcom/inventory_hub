# frozen_string_literal: true

require "bcrypt"

puts "Seeding InventoryHub database with cloud images..."

categories = %w[Equipment Furniture Book Other].index_with do |name|
  Category.find_or_create_by!(name: name)
end

default_pw = BCrypt::Password.create("password123")

users_data = [
  { name: "Alex Rivera",   email: "admin@inventoryhub.io",  admin: true,  provider: "google" },
  { name: "Elena Rostova", email: "elena@inventoryhub.io",  admin: false, provider: "github" },
  { name: "Marcus Vance",  email: "marcus@inventoryhub.io", admin: false, provider: "google" },
  { name: "Sophia Chen",   email: "sophia@inventoryhub.io", admin: false, provider: "facebook" }
]

users = users_data.map do |u|
  user = User.find_or_initialize_by(email: u[:email])
  user.assign_attributes(
    name:               u[:name],
    admin:              u[:admin],
    blocked:            false,
    provider:           u[:provider],
    uid:                "oauth-#{u[:email]}",
    encrypted_password: default_pw
  )
  user.save!
  user
end

alex, elena, marcus, sophia = users

tag_names = %w[hardware electronics components iot laptops workstation library books engineering compliance office furniture]
tags = tag_names.index_with { |name| Tag.find_or_create_by!(name: name) }

cloud_images = {
  "Semiconductor & Radio Components Vault"       => "https://images.unsplash.com/photo-1518770660439-4636190af475?w=600&auto=format&fit=crop&q=80",
  "Company Owned Computers & Workstations"       => "https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=600&auto=format&fit=crop&q=80",
  "Corporate Engineering & Architecture Library" => "https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?w=600&auto=format&fit=crop&q=80",
  "Ergonomic Office Furniture & Studio Gear"     => "https://images.unsplash.com/photo-1524758631624-e2822e304c36?w=600&auto=format&fit=crop&q=80",
  "Clinical Diagnostic Lab Instruments"          => "https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=600&auto=format&fit=crop&q=80",
  "Global Compliance & HR Contracts"             => "https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=600&auto=format&fit=crop&q=80"
}

fallback_images = cloud_images.values

inv1 = Inventory.find_or_initialize_by(title: "Semiconductor & Radio Components Vault")
inv1.assign_attributes(
  creator:          elena,
  category:         categories["Equipment"],
  description:      "High-precision inventory for microcontrollers, RF modules, voltage tolerances, and **PDF datasheets**.",
  image_url:        cloud_images["Semiconductor & Radio Components Vault"],
  is_public:        true,
  custom_id_config: [
    { "type" => "fixed",    "value" => "PART-", "format" => "" },
    { "type" => "sequence", "value" => "",      "format" => "D7" }
  ],
  custom_string1_state: true, custom_string1_name: "Model",          custom_string1_desc: "Component part number and description", custom_string1_show_in_table: true, custom_string1_position: 1,
  custom_int1_state:    true, custom_int1_name:    "Voltage (V)",    custom_int1_desc:    "Nominal operating voltage",             custom_int1_show_in_table:    true, custom_int1_position:    2,
  custom_int2_state:    true, custom_int2_name:    "Current (A)",    custom_int2_desc:    "Maximum continuous current in Amps",    custom_int2_show_in_table:    true, custom_int2_position:    3,
  custom_link1_state:   true, custom_link1_name:   "Datasheet Link", custom_link1_desc:   "Official PDF datasheet URL",            custom_link1_show_in_table:   true, custom_link1_position:   4
)
inv1.save!

parts_items = [
  ["PART-0000001", "STM32F407VGT6 ARM MCU",           3.3,  0.25, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", elena,  8.days.ago],
  ["PART-0000002", "ESP32-S3-WROOM-1 Wi-Fi/BLE",      3.3,  0.50, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", alex,   6.days.ago],
  ["PART-0000003", "LM2596 Step-Down Converter",      40.0, 3.00, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", marcus, 5.days.ago],
  ["PART-0000004", "nRF24L01+ 2.4GHz RF Transceiver",  3.6,  0.15, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", sophia, 3.days.ago],
  ["PART-0000005", "ATmega328P-PU Microcontroller",    5.0,  0.20, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", elena,  2.days.ago],
  ["PART-0000006", "ADS1115 16-Bit ADC Module",        5.5,  0.10, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", alex,   9.hours.ago]
]

parts_items.each do |cid, model, volt, amp, pdf, creator, ts|
  item = inv1.items.find_or_initialize_by(custom_id: cid)
  item.assign_attributes(
    created_by:         creator,
    custom_string1_val: model,
    custom_int1_val:    volt,
    custom_int2_val:    amp,
    custom_link1_val:   pdf
  )
  item.save!(validate: false)
  item.update_columns(created_at: ts, updated_at: ts)
end

Inventory.order(:id).each_with_index do |inv, idx|
  target_image = cloud_images[inv.title] || fallback_images[idx % fallback_images.size]
  inv.update_columns(
    image_url:  target_image,
    created_at: (idx + 1).days.ago - (idx * 4).hours
  )

  inv.items.order(:id).each_with_index do |item, i|
    next if inv.id == inv1.id

    item.update_columns(
      created_by_id: users[(idx + i) % users.size].id,
      created_at:    (i + 1).days.ago - (i * 5).hours
    )
  end
end

Inventory.find_each { |inv| Inventory.reset_counters(inv.id, :items) }
Tag.find_each { |tag| Tag.reset_counters(tag.id, :inventory_tags) }

puts "Success! All 6 inventories now have valid cloud images."