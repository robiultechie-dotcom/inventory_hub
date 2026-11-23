# frozen_string_literal: true

class CreateCustomFields < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_fields do |t|
      t.references :inventory, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string  :field_type, null: false
      t.string  :name, null: false
      t.string  :description, default: "", null: false
      t.boolean :show_in_table, default: true, null: false
      t.integer :position, default: 1, null: false

      # Section 16 optional tuning & select list options
      t.integer :min_length
      t.integer :max_length
      t.string  :regex_pattern
      t.decimal :min_value, precision: 15, scale: 4
      t.decimal :max_value, precision: 15, scale: 4
      t.text    :select_options
      t.string  :legacy_slot_key

      t.timestamps
    end

    add_index :custom_fields, [ :inventory_id, :position ]
    add_index :custom_fields, [ :inventory_id, :field_type ]
  end
end