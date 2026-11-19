# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @latest_inventories = Inventory.latest_first.limit(10)
    @popular_inventories = Inventory.top_popular(5)
    @tags = Tag.popular.limit(30)
    @max_tag_count = @tags.map(&:inventories_count).max.to_i

    @stats = {
      inventories_count: Inventory.count,
      items_count: Item.count,
      tags_count: Tag.count
    }
  end
end