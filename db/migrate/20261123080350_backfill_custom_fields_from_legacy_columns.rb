# frozen_string_literal: true

class BackfillCustomFieldsFromLegacyColumns < ActiveRecord::Migration[8.1]
  class MigrationInventory < ActiveRecord::Base
    self.table_name = "inventories"
  end

  class MigrationItem < ActiveRecord::Base
    self.table_name = "items"
  end

  class MigrationCustomField < ActiveRecord::Base
    self.table_name = "custom_fields"
  end

  class MigrationItemFieldValue < ActiveRecord::Base
    self.table_name = "item_field_values"
  end

  LEGACY_FIELD_TYPES = {
    "string" => { prefix: "custom_string" },
    "text"   => { prefix: "custom_text" },
    "int"    => { prefix: "custom_int" },
    "link"   => { prefix: "custom_link" },
    "bool"   => { prefix: "custom_bool" }
  }.freeze

  def up
    MigrationInventory.reset_column_information
    MigrationItem.reset_column_information
    MigrationCustomField.reset_column_information
    MigrationItemFieldValue.reset_column_information

    MigrationInventory.find_each do |inv|
      next if MigrationCustomField.where(inventory_id: inv.id).exists?

      slots = []
      LEGACY_FIELD_TYPES.each do |type_key, meta|
        (1..3).each do |idx|
          prefix = "#{meta[:prefix]}#{idx}"
          next unless inv.read_attribute("#{prefix}_state") == true

          name = inv.read_attribute("#{prefix}_name").to_s.strip
          next if name.blank?

          slots << {
            slot_key:      "#{type_key}#{idx}",
            field_type:    type_key,
            val_col:       "#{prefix}_val",
            name:          name,
            description:   inv.read_attribute("#{prefix}_desc").to_s.strip,
            show_in_table: inv.read_attribute("#{prefix}_show_in_table") == true,
            position:      inv.read_attribute("#{prefix}_position").to_i,
            idx:           idx
          }
        end
      end

      slots.sort_by! { |s| [ s[:position], s[:idx] ] }
      next if slots.empty?

      created_fields = slots.each_with_index.map do |slot, pos_idx|
        cf = MigrationCustomField.create!(
          inventory_id:    inv.id,
          field_type:      slot[:field_type],
          name:            slot[:name],
          description:     slot[:description],
          show_in_table:   slot[:show_in_table],
          position:        pos_idx + 1,
          legacy_slot_key: slot[:slot_key]
        )
        [ cf, slot ]
      end

      MigrationItem.where(inventory_id: inv.id).find_each do |item|
        created_fields.each do |cf, slot|
          raw_val = item.read_attribute(slot[:val_col])
          next if raw_val.nil? || (slot[:field_type] != "bool" && raw_val.to_s.blank?)

          attrs = { item_id: item.id, custom_field_id: cf.id }
          case slot[:field_type]
          when "string", "link"
            attrs[:string_value] = raw_val.to_s
          when "text"
            attrs[:text_value] = raw_val.to_s
          when "int"
            attrs[:numeric_value] = raw_val
          when "bool"
            attrs[:boolean_value] = (raw_val == true)
          end

          MigrationItemFieldValue.create!(attrs)
        end
      end
    end
  end

  def down
    MigrationCustomField.where.not(legacy_slot_key: nil).delete_all
  end
end