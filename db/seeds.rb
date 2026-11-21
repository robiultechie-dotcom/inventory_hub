# frozen_string_literal: true

require "bcrypt"

puts "==> Seeding InventoryHub database (idempotent production-ready pipeline)..."

ActiveRecord::Base.transaction do
  # 1. Categories (4)
  categories = %w[Equipment Furniture Book Other].index_with do |name|
    Category.find_or_create_by!(name: name)
  end

  # 2. Demo Users (4)
  default_pw = BCrypt::Password.create("password123")

  users_data = [
    { name: "Alex Rivera",   email: "admin@inventoryhub.io",  admin: true,  provider: "google" },
    { name: "Elena Rostova", email: "elena@inventoryhub.io",  admin: false, provider: "github" },
    { name: "Marcus Vance",  email: "marcus@inventoryhub.io", admin: false, provider: "google" },
    { name: "Sophia Chen",   email: "sophia@inventoryhub.io", admin: false, provider: "facebook" }
  ]

  users = users_data.index_by { |u| u[:email] }.transform_values do |u|
    user = User.find_or_initialize_by(email: u[:email])
    user.assign_attributes(
      name:               u[:name],
      admin:              u[:admin],
      blocked:            false,
      provider:           u[:provider],
      uid:                "oauth-#{u[:email]}",
      encrypted_password: user.encrypted_password.presence || default_pw
    )
    user.save!
    user
  end

  alex   = users.fetch("admin@inventoryhub.io")
  elena  = users.fetch("elena@inventoryhub.io")
  marcus = users.fetch("marcus@inventoryhub.io")
  sophia = users.fetch("sophia@inventoryhub.io")

  # 3. Tags (12 — exact match with Tag Cloud)
  tag_names = %w[
    hardware electronics components iot laptops office
    hr-documents compliance books library laboratory furniture
  ]
  tags = tag_names.index_with { |name| Tag.find_or_create_by!(name: name) }

  # 4. Inventories (6) + Items (21) + Tag Associations (12 active tags)
  inventories_seed = [
    {
      title:       "Semiconductor & Radio Components Vault",
      creator:     elena,
      category:    categories["Equipment"],
      description: "High-precision inventory for microcontrollers, RF modules, voltage tolerances, and **PDF datasheets**.",
      image_url:   "https://images.unsplash.com/photo-1518770660439-4636190af475?w=600&auto=format&fit=crop&q=80",
      is_public:   true,
      created_at:  1.day.ago,
      tags:        %w[hardware electronics components iot],
      custom_id_config: [
        { "type" => "fixed",    "value" => "PART-", "format" => "" },
        { "type" => "sequence", "value" => "",      "format" => "D7" }
      ],
      fields: {
        custom_string1_state: true, custom_string1_name: "Model",          custom_string1_desc: "Component part number and description", custom_string1_show_in_table: true, custom_string1_position: 1,
        custom_int1_state:    true, custom_int1_name:    "Voltage (V)",    custom_int1_desc:    "Nominal operating voltage",             custom_int1_show_in_table:    true, custom_int1_position:    2,
        custom_int2_state:    true, custom_int2_name:    "Current (A)",    custom_int2_desc:    "Maximum continuous current in Amps",    custom_int2_show_in_table:    true, custom_int2_position:    3,
        custom_link1_state:   true, custom_link1_name:   "Datasheet Link", custom_link1_desc:   "Official PDF datasheet URL",            custom_link1_show_in_table:   true, custom_link1_position:   4
      },
      items: [
        ["PART-0000001", "STM32F407VGT6 ARM MCU",          3.3,  0.25, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", elena,  8.days.ago],
        ["PART-0000002", "ESP32-S3-WROOM-1 Wi-Fi/BLE",     3.3,  0.50, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", alex,   6.days.ago],
        ["PART-0000003", "LM2596 Step-Down Converter",     40.0, 3.00, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", marcus, 5.days.ago],
        ["PART-0000004", "nRF24L01+ 2.4GHz RF Transceiver", 3.6, 0.15, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", sophia, 3.days.ago],
        ["PART-0000005", "ATmega328P-PU Microcontroller",  5.0,  0.20, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", elena,  2.days.ago],
        ["PART-0000006", "ADS1115 16-Bit ADC Module",      5.5,  0.10, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", alex,   9.hours.ago]
      ]
    },
    {
      title:       "Company Owned Computers & Workstations",
      creator:     alex,
      category:    categories["Equipment"],
      description: "Enterprise IT registry tracking MacBooks, ThinkPads, GPU servers, and automated serial IDs.",
      image_url:   "https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=600&auto=format&fit=crop&q=80",
      is_public:   true,
      created_at:  2.days.ago,
      tags:        %w[hardware laptops office],
      custom_id_config: [
        { "type" => "fixed",    "value" => "COMP-2026-", "format" => "" },
        { "type" => "sequence", "value" => "",           "format" => "D4" }
      ],
      fields: {
        custom_string1_state: true, custom_string1_name: "Hardware Model", custom_string1_desc: "Laptop or workstation model",     custom_string1_show_in_table: true, custom_string1_position: 1,
        custom_int1_state:    true, custom_int1_name:    "RAM (GB)",       custom_int1_desc:    "Installed memory capacity",       custom_int1_show_in_table:    true, custom_int1_position:    2,
        custom_int2_state:    true, custom_int2_name:    "Storage (GB)",   custom_int2_desc:    "NVMe SSD storage capacity",       custom_int2_show_in_table:    true, custom_int2_position:    3,
        custom_link1_state:   true, custom_link1_name:   "Asset Spec URL", custom_link1_desc:   "Manufacturer specification page", custom_link1_show_in_table:   true, custom_link1_position:   4
      },
      items: [
        ["COMP-2026-0001", "MacBook Pro 16 M3 Max",          64, 2000, "https://www.apple.com/macbook-pro/",            alex,   9.days.ago],
        ["COMP-2026-0002", "ThinkPad X1 Carbon Gen 12",      32, 1000, "https://www.lenovo.com/thinkpad/",              elena,  7.days.ago],
        ["COMP-2026-0003", "HP EliteBook 845 G10 Ryzen PRO", 32, 1000, "https://www.hp.com/elitebook/",                 marcus, 5.days.ago],
        ["COMP-2026-0004", "Dell Precision 7960 GPU Tower", 128, 4000, "https://www.dell.com/precision/",               sophia, 4.days.ago],
        ["COMP-2026-0005", "Mac Studio M2 Ultra",           128, 2000, "https://www.apple.com/mac-studio/",             alex,   2.days.ago]
      ]
    },
    {
      title:       "Global Compliance & HR Contracts",
      creator:     sophia,
      category:    categories["Other"],
      description: "Standardized repository for vendor SLAs, NDAs, security audits, and regulatory compliance certificates.",
      image_url:   "https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=600&auto=format&fit=crop&q=80",
      is_public:   false,
      created_at:  3.days.ago,
      tags:        %w[hr-documents office compliance],
      custom_id_config: [
        { "type" => "fixed",    "value" => "HR-DOC-", "format" => "" },
        { "type" => "sequence", "value" => "",        "format" => "D3" }
      ],
      fields: {
        custom_string1_state: true, custom_string1_name: "Document Title",  custom_string1_desc: "Official contract or audit name", custom_string1_show_in_table: true, custom_string1_position: 1,
        custom_int1_state:    true, custom_int1_name:    "Retention (Yrs)", custom_int1_desc:    "Legal archive period in years",   custom_int1_show_in_table:    true, custom_int1_position:    2,
        custom_int2_state:    true, custom_int2_name:    "Revision",        custom_int2_desc:    "Approved revision number",        custom_int2_show_in_table:    true, custom_int2_position:    3,
        custom_link1_state:   true, custom_link1_name:   "Signed PDF",      custom_link1_desc:   "Verified document URL",           custom_link1_show_in_table:   true, custom_link1_position:   4
      },
      items: [
        ["HR-DOC-001", "ISO 27001 Annual Security Audit",      7, 3, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", sophia, 10.days.ago],
        ["HR-DOC-002", "SOC 2 Type II Compliance Report",      5, 2, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", alex,   8.days.ago],
        ["HR-DOC-003", "Master Cloud Vendor SLA Agreement",    5, 4, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", marcus, 6.days.ago],
        ["HR-DOC-004", "Global Mutual NDA Template (GDPR)",   10, 5, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", elena,  3.days.ago]
      ]
    },
    {
      title:       "Corporate Engineering & Architecture Library",
      creator:     marcus,
      category:    categories["Book"],
      description: "Internal technical book collection with author metadata, publication years, and review annotations.",
      image_url:   "https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?w=600&auto=format&fit=crop&q=80",
      is_public:   false,
      created_at:  4.days.ago,
      tags:        %w[books library],
      custom_id_config: [
        { "type" => "fixed",    "value" => "LIB-BK-", "format" => "" },
        { "type" => "sequence", "value" => "",        "format" => "D3" }
      ],
      fields: {
        custom_string1_state: true, custom_string1_name: "Book & Author", custom_string1_desc: "Title and primary author",  custom_string1_show_in_table: true, custom_string1_position: 1,
        custom_int1_state:    true, custom_int1_name:    "Year",          custom_int1_desc:    "Year of publication",       custom_int1_show_in_table:    true, custom_int1_position:    2,
        custom_int2_state:    true, custom_int2_name:    "Copies",        custom_int2_desc:    "Physical copies in shelf",  custom_int2_show_in_table:    true, custom_int2_position:    3,
        custom_link1_state:   true, custom_link1_name:   "Reference URL", custom_link1_desc:   "Publisher catalog page",    custom_link1_show_in_table:   true, custom_link1_position:   4
      },
      items: [
        ["LIB-BK-001", "Designing Data-Intensive Applications — Martin Kleppmann", 2017, 4, "https://dataintensive.net/",                 marcus, 11.days.ago],
        ["LIB-BK-002", "Clean Architecture — Robert C. Martin",                    2017, 3, "https://www.oreilly.com/",                   elena,  7.days.ago],
        ["LIB-BK-003", "Site Reliability Engineering — Betsy Beyer et al.",        2016, 2, "https://sre.google/books/",                  alex,   4.days.ago]
      ]
    },
    {
      title:       "Clinical Diagnostic Lab Instruments",
      creator:     elena,
      category:    categories["Equipment"],
      description: "Calibration logs, maintenance schedules, and sensor specs for optical & chemical testing gear.",
      image_url:   "https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=600&auto=format&fit=crop&q=80",
      is_public:   true,
      created_at:  5.days.ago,
      tags:        %w[hardware laboratory iot],
      custom_id_config: [
        { "type" => "fixed",    "value" => "LAB-BIO-", "format" => "" },
        { "type" => "sequence", "value" => "",         "format" => "D3" }
      ],
      fields: {
        custom_string1_state: true, custom_string1_name: "Instrument Model",    custom_string1_desc: "Diagnostic hardware name",       custom_string1_show_in_table: true, custom_string1_position: 1,
        custom_int1_state:    true, custom_int1_name:    "Cal. Interval (Days)", custom_int1_desc:   "Calibration cycle in days",      custom_int1_show_in_table:    true, custom_int1_position:    2,
        custom_int2_state:    true, custom_int2_name:    "Power (W)",           custom_int2_desc:    "Rated power consumption",        custom_int2_show_in_table:    true, custom_int2_position:    3,
        custom_link1_state:   true, custom_link1_name:   "Manual PDF",          custom_link1_desc:   "Calibration and service manual", custom_link1_show_in_table:   true, custom_link1_position:   4
      },
      items: [
        ["LAB-BIO-001", "UV-Vis Spectrophotometer Lambda 365", 90,  180, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", elena,  12.days.ago],
        ["LAB-BIO-002", "Automated PCR Thermal Cycler Pro",    180, 450, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", sophia, 6.days.ago]
      ]
    },
    {
      title:       "Ergonomic Office Furniture & Studio Gear",
      creator:     alex,
      category:    categories["Furniture"],
      description: "Tracking motorized standing desks, Herman Miller chairs, and acoustic studio panels across floors.",
      image_url:   "https://images.unsplash.com/photo-1524758631624-e2822e304c36?w=600&auto=format&fit=crop&q=80",
      is_public:   true,
      created_at:  6.days.ago,
      tags:        %w[office furniture],
      custom_id_config: [
        { "type" => "fixed",    "value" => "FURN-HQ-", "format" => "" },
        { "type" => "sequence", "value" => "",         "format" => "D3" }
      ],
      fields: {
        custom_string1_state: true, custom_string1_name: "Asset Name",    custom_string1_desc: "Furniture brand and model",  custom_string1_show_in_table: true, custom_string1_position: 1,
        custom_int1_state:    true, custom_int1_name:    "Floor",         custom_int1_desc:    "Building floor location",    custom_int1_show_in_table:    true, custom_int1_position:    2,
        custom_int2_state:    true, custom_int2_name:    "Quantity",      custom_int2_desc:    "Total deployed units",       custom_int2_show_in_table:    true, custom_int2_position:    3,
        custom_link1_state:   true, custom_link1_name:   "Warranty Link", custom_link1_desc:   "Vendor warranty document",   custom_link1_show_in_table:   true, custom_link1_position:   4
      },
      items: [
        ["FURN-HQ-001", "Herman Miller Aeron Ergonomic Chair (Size B)", 4, 24, "https://www.hermanmiller.com/", alex, 14.days.ago]
      ]
    }
  ]

  inventories_seed.each do |spec|
    inv = Inventory.find_or_initialize_by(title: spec[:title])
    inv.assign_attributes(
      creator:          spec[:creator],
      category:         spec[:category],
      description:      spec[:description],
      image_url:        spec[:image_url],
      is_public:        spec[:is_public],
      custom_id_config: spec[:custom_id_config],
      **spec[:fields]
    )
    inv.save!
    inv.update_columns(created_at: spec[:created_at], updated_at: spec[:created_at])

    # Attach exact tags without duplicates
    spec[:tags].each do |tag_name|
      tag = tags.fetch(tag_name)
      inv.tags << tag unless inv.tags.exists?(tag.id)
    end

    # Seed items idempotently
    spec[:items].each do |cid, str1, int1, int2, link1, item_creator, ts|
      item = inv.items.find_or_initialize_by(custom_id: cid)
      item.assign_attributes(
        created_by:         item_creator,
        custom_string1_val: str1,
        custom_int1_val:    int1,
        custom_int2_val:    int2,
        custom_link1_val:   link1
      )
      item.save!(validate: false)
      item.update_columns(created_at: ts, updated_at: ts)
    end
  end

  # 5. Reset all counter caches so UI badges & Tag Cloud match 100%
  Inventory.find_each { |inv| Inventory.reset_counters(inv.id, :items) }
  Tag.find_each       { |tag| Tag.reset_counters(tag.id, :inventory_tags) }

  # 6. Guarantee ADMIN_EMAIL stays admin on every deploy
  if ENV["ADMIN_EMAIL"].present?
    admin_user = User.find_by("LOWER(email) = ?", ENV["ADMIN_EMAIL"].strip.downcase)
    admin_user&.update_columns(admin: true, blocked: false)
  end

  # 7. Fail-Loud Post-Seed Integrity Assertions (Zero Missing Data Guarantee)
  active_tags = Tag.joins(:inventory_tags).distinct.count
  raise "Seed integrity error: expected >= 4 categories, got #{Category.count}"     if Category.count < 4
  raise "Seed integrity error: expected >= 6 inventories, got #{Inventory.count}"   if Inventory.count < 6
  raise "Seed integrity error: expected >= 21 items, got #{Item.count}"             if Item.count < 21
  raise "Seed integrity error: expected >= 12 active tags, got #{active_tags}"      if active_tags < 12

  puts "==> Seed verified! Categories: #{Category.count}, Inventories: #{Inventory.count}, Items: #{Item.count}, Active Tags: #{active_tags}"
end