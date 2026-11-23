# frozen_string_literal: true

require "set"

class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @tag   = params[:tag].to_s.strip.downcase

    @inventories = if @tag.present?
                     Inventory.where(
                       "EXISTS (SELECT 1 FROM inventory_tags INNER JOIN tags ON tags.id = inventory_tags.tag_id " \
                       "WHERE inventory_tags.inventory_id = inventories.id AND LOWER(tags.name) = ?)",
                       @tag
                     ).includes(:category, :creator, :tags).order(created_at: :desc)
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

    @writable_inventory_ids = preload_writable_inventory_ids(@items)
  end

  def suggestions
    q = params[:q].to_s.strip
    inventories = if q.present?
                    Inventory.full_text_search(q).includes(:category, :creator).limit(5)
    else
                    Inventory.includes(:category, :creator).order(created_at: :desc).limit(5)
    end

    items = if q.present?
              Item.full_text_search(q).includes(:inventory).limit(5).to_a
    else
              []
    end
    writable_ids = preload_writable_inventory_ids(items)

    tags = Tag.popular
    if q.present?
      tsq = Inventory.build_fts_query(q)
      if tsq.present?
        tags = tags.where("to_tsvector('simple', coalesce(tags.name, '')) @@ to_tsquery('simple', ?)", tsq)
      else
        tags = tags.where("LOWER(tags.name) LIKE ?", "#{Tag.sanitize_sql_like(q.downcase)}%")
      end
    end
    tags = tags.limit(5)

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
        item_url = writable_ids.include?(item.inventory_id) ? edit_inventory_item_path(item.inventory, item) : inventory_item_path(item.inventory, item)
        {
          url:             item_url,
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

  private

  # Batch-resolves write permissions in at most 1 query (prevents N+1 queries inside view loops)
  def preload_writable_inventory_ids(items_list)
    return Set.new if current_user.nil? || items_list.empty?

    inv_ids = items_list.map(&:inventory_id).uniq
    return inv_ids.to_set if current_user.admin?

    direct_ids = items_list.map(&:inventory).compact.select do |inv|
      inv.is_public? || inv.creator_id == current_user.id
    end.map(&:id).uniq

    remaining_ids = inv_ids - direct_ids
    granted_ids = if remaining_ids.any?
                    InventoryAccess.where(user_id: current_user.id, inventory_id: remaining_ids).pluck(:inventory_id)
    else
                    []
    end

    (direct_ids + granted_ids).to_set
  end
end
