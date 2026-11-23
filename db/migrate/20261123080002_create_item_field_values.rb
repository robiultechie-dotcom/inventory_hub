# frozen_string_literal: true

class CreateItemFieldValues < ActiveRecord::Migration[8.1]
  def change
    create_table :item_field_values do |t|
      t.references :item, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :custom_field, null: false, foreign_key: { on_delete: :cascade }
      t.string  :string_value
      t.text    :text_value
      t.decimal :numeric_value, precision: 15, scale: 4
      t.boolean :boolean_value

      t.timestamps
    end

    add_index :item_field_values, [ :item_id, :custom_field_id ], unique: true
    add_index :item_field_values, [ :custom_field_id, :numeric_value ]
    add_index :item_field_values, [ :custom_field_id, :string_value ]
  end
end
