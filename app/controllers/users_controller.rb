# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!, only: %i[autocomplete]

  def show
    @user = User.find(params[:id])

    owned_base = @user.owned_inventories.includes(:category, :creator, :tags)
    @owned_inventories = filter_and_sort(
      owned_base,
      query:       params[:owned_q],
      category_id: params[:owned_category_id],
      sort:        params[:owned_sort]
    )

    # Uses EXISTS subquery instead of LEFT JOIN + DISTINCT so PostgreSQL safely supports ORDER BY LOWER(title)
    writable_base = if @user.admin?
                      Inventory.where.not(creator_id: @user.id)
    else
                      Inventory.where.not(creator_id: @user.id)
                               .where(
                                 "inventories.is_public = TRUE OR EXISTS (" \
                                 "SELECT 1 FROM inventory_accesses " \
                                 "WHERE inventory_accesses.inventory_id = inventories.id " \
                                 "AND inventory_accesses.user_id = ?)",
                                 @user.id
                               )
    end

    @writable_inventories = filter_and_sort(
      writable_base.includes(:category, :creator, :tags),
      query:       params[:access_q],
      category_id: params[:access_category_id],
      sort:        params[:access_sort]
    )
  end

  # Section 5: Requires minimum 2 characters to prevent user email enumeration
  def autocomplete
    q = params[:q].to_s.strip
    if q.length < 2
      render json: []
      return
    end

    like = "%#{User.sanitize_sql_like(q)}%"
    scope = User.where(blocked: false)
                .where("name ILIKE :q OR email ILIKE :q", q: like)
                .order(Arel.sql("LOWER(name) ASC"))
                .limit(10)

    render json: scope.map { |u| { name: u.name, email: u.email, label: "#{u.name} (#{u.email})" } }
  end

  private

  def filter_and_sort(scope, query:, category_id:, sort:)
    rel = scope
    rel = rel.merge(Inventory.full_text_search(query)) if query.present?
    rel = rel.where(category_id: category_id) if category_id.present?

    case sort
    when "oldest"     then rel.order(created_at: :asc)
    when "title_asc"  then rel.order(Arel.sql("LOWER(inventories.title) ASC"))
    when "title_desc" then rel.order(Arel.sql("LOWER(inventories.title) DESC"))
    when "most_items" then rel.order(items_count: :desc, created_at: :desc)
    else                   rel.order(created_at: :desc)
    end
  end
end
