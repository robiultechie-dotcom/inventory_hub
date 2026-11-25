# frozen_string_literal: true

require "set"

class InventoriesController < ApplicationController
  ITEMS_PER_PAGE     = 50
  ALLOWED_ITEM_SORTS = %w[ newest oldest id_asc id_desc likes_desc ].freeze

  before_action :authenticate_user!, except: %i[ index show ]
  before_action :set_inventory, only: %i[
    show update destroy update_custom_id update_fields
    grant_access revoke_access export_items_csv export_items_xlsx
  ]
  before_action :authorize_manager!, only: %i[
    update destroy update_custom_id update_fields
    grant_access revoke_access export_items_csv export_items_xlsx
  ]

  def index
    redirect_to root_path
  end

  def show
    @active_tab           = params[:tab].presence || "items"
    @active_tab           = "items" if %w[ settings custom_id fields access stats export ].include?(@active_tab) && !@inventory.manageable_by?(current_user)
    @custom_fields        = @inventory.ordered_custom_fields
    @dynamic_table_fields = @inventory.dynamic_table_fields
    @id_generator         = CustomIdGenerator.new(@inventory)

    @item_query          = params[:item_q].to_s.strip
    @item_sort           = ALLOWED_ITEM_SORTS.include?(params[:item_sort]) ? params[:item_sort] : "newest"
    filtered_items_scope = filter_items(Item.where(inventory_id: @inventory.id), @item_query)
    total_items_count    = @item_query.present? ? filtered_items_scope.count : @inventory.items_count
    @total_pages         = [ (total_items_count.to_f / ITEMS_PER_PAGE).ceil, 1 ].max
    @page                = params[:page].to_i.clamp(1, @total_pages)
    @items               = sort_items(filtered_items_scope, @item_sort)
                             .includes(:created_by, :item_field_values)
                             .offset((@page - 1) * ITEMS_PER_PAGE)
                             .limit(ITEMS_PER_PAGE)
                             .to_a

    @liked_item_ids = Set.new
    if current_user && @items.any?
      @liked_item_ids = current_user.likes.where(item_id: @items.map(&:id)).pluck(:item_id).to_set
    end

    @comments = @inventory.comments.includes(:user)

    if @inventory.manageable_by?(current_user)
      sort_col = params[:access_sort] == "email" ? "LOWER(users.email) ASC" : "LOWER(users.name) ASC"
      @access_records = @inventory.inventory_accesses.joins(:user).includes(:user).order(Arel.sql(sort_col))
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

    elements = []
    unless params[:clear_all] == "1"
      elements = Array(params[:elements]).filter_map do |el|
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

    if params[:custom_fields_submitted] == "1" || params.key?(:custom_fields)
      @inventory.sync_custom_fields_params!(dynamic_custom_fields_params)
    else
      @inventory.apply_custom_fields_params!(params[:fields])
    end

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

    send_data InventoryExporter.inventories_to_csv(inventories),
              filename: "inventories-#{Date.current}.csv",
              type:     InventoryExporter::CSV_MIME_TYPE
  end

  def export_items_csv
    exporter = InventoryExporter.new(@inventory)
    send_data exporter.to_csv,
              filename: "inventory-#{@inventory.id}-items.csv",
              type:     InventoryExporter::CSV_MIME_TYPE
  end

  def export_items_xlsx
    exporter = InventoryExporter.new(@inventory)
    send_data exporter.to_xlsx,
              filename: "inventory-#{@inventory.id}-items.xlsx",
              type:     InventoryExporter::EXCEL_MIME_TYPE
  end

  private

  def filter_items(scope, query)
    return scope if query.blank?

    like_q      = "%#{Item.sanitize_sql_like(query)}%"
    fts_scope   = scope.merge(Item.full_text_search(query))
    extra_scope = scope.where(
      "EXISTS (SELECT 1 FROM users WHERE users.id = items.created_by_id AND users.name ILIKE :like_q) " \
      "OR EXISTS (SELECT 1 FROM item_field_values WHERE item_field_values.item_id = items.id AND CAST(item_field_values.numeric_value AS TEXT) ILIKE :like_q)",
      like_q: like_q
    )

    fts_scope.or(extra_scope)
  end

  def sort_items(scope, sort_mode)
    case sort_mode
    when "oldest"     then scope.order(created_at: :asc, id: :asc)
    when "id_asc"     then scope.order(Arel.sql("LOWER(items.custom_id) ASC"), id: :asc)
    when "id_desc"    then scope.order(Arel.sql("LOWER(items.custom_id) DESC"), id: :desc)
    when "likes_desc" then scope.order(likes_count: :desc, created_at: :desc, id: :desc)
    else                   scope.order(created_at: :desc, id: :desc)
    end
  end

  def set_inventory
    @inventory = Inventory.includes(:custom_fields).find(params[:id])
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

  def dynamic_custom_fields_params
    raw_list = params[:custom_fields]
    return [] unless raw_list.is_a?(Array) || raw_list.is_a?(ActionController::Parameters)

    entries = raw_list.is_a?(Array) ? raw_list : raw_list.values
    entries.filter_map do |entry|
      next unless entry.is_a?(ActionController::Parameters)

      entry.permit(
        :id, :field_type, :name, :description, :show_in_table, :position,
        :min_length, :max_length, :regex_pattern, :min_value, :max_value,
        :select_options, :_destroy
      ).to_h
    end
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
    saved_fields = @inventory.custom_fields.reload.to_a

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
          active_fields_count: saved_fields.size,
          custom_fields:       saved_fields.map { |cf| { id: cf.id, name: cf.name, field_type: cf.field_type, position: cf.position } },
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