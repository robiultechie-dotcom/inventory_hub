# frozen_string_literal: true

class InventoryTag < ApplicationRecord
  belongs_to :inventory
  belongs_to :tag, counter_cache: :inventories_count

  validates :tag_id, uniqueness: { scope: :inventory_id }
end
