# frozen_string_literal: true

require "set"

class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @tag   = params[:tag].to_s.strip.downcase

    @inventories = if @tag.present?
                     Inventory.joins(:tags)
                              .where("LOWER(tags.name) = ?", @tag)
                              .includes(:category, :creator, :tags)
                              .order(created_at: :desc)
                              .distinct
                   elsif @query.present?
                     Inventory.full_text_search(@query)
                              .includes(:category, :creator, :tags)
                              .order(created_at: :desc)
                              .limit(50)
                   else
                     Inventory.none
                   end

    @items = if @query.present?
               Item.full_text_search(@query)
                   .includes(:inventory, :created_by)
                   .order(created_at: :desc)
                   .limit(50)
                   .to_a
             else
               []
             end

    @liked_item_ids = if current_user && @items.any?
                        current_user.likes.where(item_id: @items.map(&:id)).pluck(:item_id).to_set
                      else
                        Set.new
                      end
  end

  def suggestions
    q = params[:q].to_s.strip
    inventories = if q.present?
                    Inventory.full_text_search(q).includes(:category, :creator).limit(5)
                  else
                    Inventory.includes(:category, :creator).order(created_at: :desc).limit(5)
                  end

    items = if q.present?
              Item.full_text_search(q).includes(:inventory).limit(5)
            else
              Item.none
            end

    tags = if q.present?
             Tag.where("name ILIKE ?", "#{Tag.sanitize_sql_like(q.downcase)}%").order(inventories_count: :desc).limit(5)
           else
             Tag.where("inventories_count > 0").order(inventories_count: :desc).limit(5)
           end

    render json: {
      inventories: inventories.map do |inv|
        {
          url:         inventory_path(inv),
          title:       inv.title,
          category:    helpers.localized_category_name(inv.category),
          creator:     inv.creator.name,
          items_count: inv.items_count
        }
      end,
      items: items.map do |item|
        {
          url:             inventory_item_path(item.inventory, item),
          custom_id:       item.custom_id,
          label:           item.primary_label,
          inventory_title: item.inventory.title
        }
      end,
      tags: tags.map do |tag|
        {
          url:   search_path(tag: tag.name),
          name:  tag.name,
          count: tag.inventories_count
        }
      end
    }
  end
end