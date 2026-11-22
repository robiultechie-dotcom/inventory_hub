# frozen_string_literal: true

class Like < ApplicationRecord
  belongs_to :item, counter_cache: true
  belongs_to :user

  validates :user_id, uniqueness: { scope: :item_id }
end
