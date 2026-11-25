# frozen_string_literal: true

class ItemsController < ApplicationController
  before_action :authenticate_user!, except: %i[show]
  before_action :set_inventory
  before_action :set_item, only: %i[show edit update toggle_like]
  before_action :authorize_writer!, only: %i[new create edit update bulk_destroy]

  def show
    @custom_fields = @inventory.ordered_custom_fields
  end

  def new
    @custom_fields = @inventory.ordered_custom_fields
    generated_id   = CustomIdGenerator.new(@inventory).generate(preview: false)
    @item          = @inventory.items.build(custom_id: generated_id)
  end

  def create
    @custom_fields  = @inventory.ordered_custom_fields
    submitted_attrs = item_params.to_h

    if submitted_attrs["custom_id"].to_s.strip.blank?
      submitted_attrs["custom_id"] = CustomIdGenerator.new(@inventory).generate(preview: false, timestamp: Time.current)
    end

    @item = @inventory.items.build(submitted_attrs)
    @item.created_by = current_user
    @item.assign_dynamic_field_values(permitted_dynamic_field_values) if params.key?(:field_values)

    if @item.save
      redirect_to inventory_path(@inventory, tab: "items"), notice: t("flashes.item_created")
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @item.errors.add(:custom_id, :taken)
    render :new, status: :unprocessable_entity
  end

  def edit
    @custom_fields = @inventory.ordered_custom_fields
  end

  def update
    @custom_fields    = @inventory.ordered_custom_fields
    submitted_version = params.dig(:item, :lock_version)
    force_overwrite   = params[:force_overwrite] == "1"

    if !force_overwrite && submitted_version.present? && submitted_version.to_i != @item.lock_version
      raise ActiveRecord::StaleObjectError.new(@item, "update")
    end

    attrs = force_overwrite ? item_params.except(:lock_version) : item_params
    @item.assign_attributes(attrs)
    @item.assign_dynamic_field_values(permitted_dynamic_field_values) if params.key?(:field_values)

    if @item.save
      redirect_to inventory_path(@inventory, tab: "items"), notice: t("flashes.item_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    @conflict_detected = true
    stale_version = params.dig(:item, :lock_version) || @item.lock_version
    @item.assign_attributes(item_params.except(:lock_version))
    @item.assign_dynamic_field_values(permitted_dynamic_field_values) if params.key?(:field_values)
    @item.lock_version = stale_version
    render :edit, status: :conflict
  rescue ActiveRecord::RecordNotUnique
    @item.errors.add(:custom_id, :taken)
    render :edit, status: :unprocessable_entity
  end

  def bulk_destroy
    ids = Array(params[:ids]).map(&:to_i)
    @inventory.items.where(id: ids).destroy_all
    Inventory.reset_counters(@inventory.id, :items)
    redirect_to inventory_path(@inventory, tab: "items"), notice: t("flashes.items_deleted")
  end

  def toggle_like
    existing_like = @item.likes.find_by(user_id: current_user.id)
    liked = if existing_like
      existing_like.destroy
      false
    else
      @item.likes.create!(user: current_user)
      true
    end

    @item.reload
    respond_to do |format|
      format.json { render json: { liked: liked, likes_count: @item.likes_count } }
      format.html { redirect_back(fallback_location: inventory_path(@inventory, tab: "items")) }
    end
  rescue ActiveRecord::RecordNotUnique
    @item.reload
    respond_to do |format|
      format.json { render json: { liked: true, likes_count: @item.likes_count } }
      format.html { redirect_back(fallback_location: inventory_path(@inventory, tab: "items")) }
    end
  end

  private

  def set_inventory
    @inventory = Inventory.includes(:custom_fields).find(params[:inventory_id])
  end

  def set_item
    @item = @inventory.items.includes(:item_field_values).find(params[:id])
  end

  def authorize_writer!
    return if @inventory.writable_by?(current_user)

    redirect_to inventory_path(@inventory), alert: t("flashes.write_access_required")
  end

  def item_params
    params.require(:item).permit(
      :custom_id, :lock_version,
      :custom_string1_val, :custom_string2_val, :custom_string3_val,
      :custom_text1_val,   :custom_text2_val,   :custom_text3_val,
      :custom_int1_val,    :custom_int2_val,    :custom_int3_val,
      :custom_link1_val,   :custom_link2_val,   :custom_link3_val,
      :custom_bool1_val,   :custom_bool2_val,   :custom_bool3_val
    )
  end

  def permitted_dynamic_field_values
    raw = params[:field_values]
    return {} unless raw.is_a?(ActionController::Parameters)

    allowed_keys = @inventory.ordered_custom_fields.map { |cf| cf.id.to_s }
    raw.permit(*allowed_keys).to_h
  end
end
