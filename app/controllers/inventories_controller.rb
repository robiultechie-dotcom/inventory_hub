# frozen_string_literal: true

require "csv"
require "set"

class InventoriesController < ApplicationController
  ITEMS_PER_PAGE = 50

  before_action :authenticate_user!, except: %i[index show]
  before_action :set_inventory, only: %i[
    show update destroy update_custom_id update_fields
    grant_access revoke_access export_items_csv
  ]
  before_action :authorize_manager!, only: %i[
    update destroy update_custom_id update_fields
    grant_access revoke_access export_items_csv
  ]

  def index
    redirect_to root_path
  end

  def show
    @active_tab   = params[:tab].presence || "items"
    @active_tab   = "items" if %w[settings custom_id fields access stats export].include?(@active_tab) && !@inventory.manageable_by?(current_user)
    @table_fields = @inventory.table_custom_fields
    @id_generator = CustomIdGenerator.new(@inventory)

    items_scope        = @inventory.items.includes(:created_by).order(created_at: :desc)
    @total_items_count = @inventory.items_count
    @total_pages       = [ (@total_items_count.to_f / ITEMS_PER_PAGE).ceil, 1 ].max
    @page              = params[:page].to_i.clamp(1, @total_pages)
    @items             = items_scope.offset((@page - 1) * ITEMS_PER_PAGE).limit(ITEMS_PER_PAGE).to_a

    @liked_item_ids = if current_user && @items.any?
                        current_user.likes.where(item_id: @items.map(&:id)).pluck(:item_id).to_set
    else
                        Set.new
    end

    @comments = @inventory.comments.includes(:user)

    if @inventory.manageable_by?(current_user)
      sort_col = params[:access_sort] == "email" ? "users.email ASC" : "users.name ASC"
      @access_records = @inventory.inventory_accesses.includes(:user).references(:user).order(Arel.sql(sort_col))
      @statistics     = @inventory.statistics if @active_tab == "stats"
    end
  end

  def create
    @inventory = current_user.owned_inventories.build(inventory_params)
    if @inventory.save
      redirect_to inventory_path(@inventory), notice: t("flashes.inventory_created")
    else
      redirect_back(fallback_location: root_path, alert: @inventory.errors.full_messages.to_sentence)
    end
  end

  def update
    target_tab = params[:tab].presence || "settings"
    verify_lock_version!(params.dig(:inventory, :lock_version))
    @inventory.assign_attributes(inventory_params)
    @inventory.lock_version = params.dig(:inventory, :lock_version).to_i if enforce_lock?(params.dig(:inventory, :lock_version))

    if @inventory.save
      render_save_success(t("flashes.inventory_updated"), target_tab)
    else
      render_save_error(@inventory.errors.full_messages.to_sentence, target_tab)
    end
  rescue ActiveRecord::StaleObjectError
    render_conflict_response
  end

  def update_custom_id
    verify_lock_version!(params[:lock_version])

    elements = if params[:clear_all] == "1"
                 []
    else
                 Array(params[:elements]).filter_map do |el|
                   type = el[:type].to_s
                   next unless CustomIdGenerator::SUPPORTED_ELEMENTS.key?(type)

                   spec = el[:spec].to_s
                   {
                     "type"   => type,
                     "value"  => type == "fixed" ? spec : "",
                     "format" => type == "fixed" ? "" : spec
                   }
                 end.first(10)
    end

    @inventory.lock_version = params[:lock_version].to_i if enforce_lock?(params[:lock_version])
    @inventory.custom_id_config = elements

    if @inventory.save
      render_save_success(t("flashes.custom_id_updated"), "custom_id")
    else
      render_save_error(@inventory.errors.full_messages.to_sentence, "custom_id")
    end
  rescue ActiveRecord::StaleObjectError
    render_conflict_response
  end

  def update_fields
    verify_lock_version!(params[:lock_version])
    @inventory.lock_version = params[:lock_version].to_i if enforce_lock?(params[:lock_version])
    @inventory.apply_custom_fields_params!(params[:fields])

    if @inventory.save
      render_save_success(t("flashes.fields_updated"), "fields")
    else
      render_save_error(@inventory.errors.full_messages.to_sentence, "fields")
    end
  rescue ActiveRecord::StaleObjectError
    render_conflict_response
  end

  def grant_access
    identifier = params[:user_identifier].to_s.strip
    user = User.find_by("LOWER(email) = LOWER(:q) OR LOWER(name) = LOWER(:q)", q: identifier)

    if user.nil?
      redirect_to inventory_path(@inventory, tab: "access"), alert: t("flashes.user_not_found")
    elsif user.id == @inventory.creator_id
      redirect_to inventory_path(@inventory, tab: "access"), alert: t("flashes.owner_already_has_access")
    else
      @inventory.inventory_accesses.find_or_create_by!(user: user)
      redirect_to inventory_path(@inventory, tab: "access"), notice: t("flashes.access_granted", name: user.name)
    end
  end

  def revoke_access
    ids = Array(params[:ids]).map(&:to_i)
    @inventory.inventory_accesses.where(id: ids).destroy_all
    redirect_to inventory_path(@inventory, tab: "access"), notice: t("flashes.access_revoked")
  end

  def destroy
    @inventory.destroy
    redirect_to user_path(current_user), notice: t("flashes.inventory_deleted")
  end

  def bulk_destroy
    ids = Array(params[:ids]).map(&:to_i)
    scope = current_user.admin? ? Inventory.where(id: ids) : current_user.owned_inventories.where(id: ids)
    scope.destroy_all
    redirect_back(fallback_location: user_path(current_user), notice: t("flashes.inventories_deleted"))
  end

  def export_csv
    ids = Array(params[:ids]).map(&:to_i)
    inventories = ids.any? ? Inventory.where(id: ids).includes(:category, :creator) : Inventory.includes(:category, :creator).limit(50)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [ "ID", "Title", "Category", "Creator", "Public", "Items Count", "Created At" ]
      inventories.each do |inv|
        csv << [ inv.id, inv.title, inv.category.name, inv.creator.name, inv.is_public, inv.items_count, inv.created_at.iso8601 ]
      end
    end

    send_data csv_data, filename: "inventories-#{Date.current}.csv", type: "text/csv; charset=utf-8"
  end

  def export_items_csv
    active_fields = @inventory.active_custom_fields
    items = @inventory.items.includes(:created_by).order(created_at: :asc)

    csv_data = CSV.generate(headers: true) do |csv|
      headers = [ "Custom ID", "Creator", "Created At", "Likes" ] + active_fields.map { |f| f[:name] }
      csv << headers
      items.each do |item|
        row = [ item.custom_id, item.created_by.name, item.created_at.iso8601, item.likes_count ]
        row.concat(active_fields.map { |f| item.public_send(f[:value_column]) })
        csv << row
      end
    end

    send_data csv_data, filename: "inventory-#{@inventory.id}-items.csv", type: "text/csv; charset=utf-8"
  end

  private

  def set_inventory
    @inventory = Inventory.find(params[:id])
  end

  def authorize_manager!
    return if @inventory.manageable_by?(current_user)

    respond_to do |format|
      format.json { render json: { message: t("flashes.unauthorized") }, status: :forbidden }
      format.html { redirect_to inventory_path(@inventory), alert: t("flashes.unauthorized") }
    end
  end

  def inventory_params
    params.require(:inventory).permit(:title, :description, :category_id, :image_url, :is_public, :tag_list)
  end

  def enforce_lock?(submitted_version)
    params[:force_overwrite] != "1" && submitted_version.present?
  end

  def verify_lock_version!(submitted_version)
    return unless enforce_lock?(submitted_version)

    if submitted_version.to_i != @inventory.lock_version
      raise ActiveRecord::StaleObjectError.new(@inventory, "update")
    end
  end

  def render_save_success(notice_msg, tab)
    generator = CustomIdGenerator.new(@inventory)
    respond_to do |format|
      format.json do
        render json: {
          status:              "saved",
          lock_version:        @inventory.lock_version,
          saved_at:            Time.current.strftime("%H:%M:%S"),
          id_preview:          generator.generate(preview: true),
          next_seq:            generator.next_sequence_number,
          title:               @inventory.title,
          category_name:       helpers.localized_category_name(@inventory.category),
          category_icon:       helpers.category_icon_class(@inventory.category.name),
          is_public:           @inventory.is_public?,
          visibility_label:    @inventory.is_public? ? t("common.public") : t("common.restricted"),
          description_html:    helpers.render_markdown(@inventory.description).to_s,
          active_fields_count: @inventory.active_custom_fields.size,
          tags:                @inventory.tags.map { |tag| { name: tag.name, url: search_path(tag: tag.name) } }
        }
      end
      format.html { redirect_to inventory_path(@inventory, tab: tab), notice: notice_msg }
    end
  end

  def render_save_error(error_msg, tab)
    respond_to do |format|
      format.json { render json: { status: "error", message: error_msg }, status: :unprocessable_entity }
      format.html { redirect_to inventory_path(@inventory, tab: tab), alert: error_msg }
    end
  end

  def render_conflict_response
    fresh_version = Inventory.where(id: @inventory.id).pick(:lock_version)
    respond_to do |format|
      format.json do
        render json: {
          status:          "conflict",
          current_version: fresh_version,
          message:         t("inventory.conflict_msg")
        }, status: :conflict
      end
      format.html do
        redirect_to inventory_path(@inventory, tab: params[:tab] || "settings"), alert: t("inventory.conflict_msg")
      end
    end
  end
end
