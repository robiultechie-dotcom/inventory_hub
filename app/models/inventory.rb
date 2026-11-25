# frozen_string_literal: true

require "set"

class Inventory < ApplicationRecord
  self.locking_column = :lock_version

  FIELD_TYPES = {
    "string" => { label: "Single-Line Text", prefix: "custom_string", count: 3 },
    "text"   => { label: "Multi-Line Text",  prefix: "custom_text",   count: 3 },
    "int"    => { label: "Numeric",          prefix: "custom_int",    count: 3 },
    "link"   => { label: "Document/Image",   prefix: "custom_link",   count: 3 },
    "bool"   => { label: "True/False",       prefix: "custom_bool",   count: 3 }
  }.freeze

  belongs_to :creator, class_name: "User", inverse_of: :owned_inventories
  belongs_to :category

  has_many :custom_fields, -> { order(:position, :id) }, dependent: :destroy, autosave: true, validate: false
  has_many :items, dependent: :destroy
  has_many :comments, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :inventory_accesses, dependent: :destroy
  has_many :authorized_users, through: :inventory_accesses, source: :user
  has_many :inventory_tags, dependent: :destroy
  has_many :tags, through: :inventory_tags

  validates :title, presence: true, length: { maximum: 160 }
  validates :image_url,
            allow_blank: true,
            length: { maximum: 500 },
            format: {
              with: /\Ahttps?:\/\/\S+\z/i,
              message: ->(_obj, _data) { I18n.t("items.invalid_link_url", default: "must be a valid http:// or https:// URL") }
            }

  validate :validate_dynamic_custom_fields

  before_create :set_default_custom_id_config
  after_save :persist_pending_tags
  after_save :clear_removed_legacy_item_columns

  scope :latest_first, -> { includes(:category, :creator, :tags).order(created_at: :desc) }
  scope :top_popular, ->(limit_count = 5) { includes(:category, :creator).order(items_count: :desc, created_at: :desc).limit(limit_count) }

  def self.build_fts_query(query)
    tokens = query.to_s.scan(/[[:alnum:]]+/).map(&:downcase).reject(&:blank?).first(8)
    return nil if tokens.empty?

    tokens.map { |token| "#{token}:*" }.join(" & ")
  end

  scope :full_text_search, lambda { |query|
    q = query.to_s.strip
    return none if q.blank?

    tsq = build_fts_query(q)
    if tsq.present?
      where(
        "to_tsvector('simple', coalesce(inventories.title, '') || ' ' || coalesce(inventories.description, '')) @@ to_tsquery('simple', :tsq) " \
        "OR EXISTS (" \
          "SELECT 1 FROM inventory_tags INNER JOIN tags ON tags.id = inventory_tags.tag_id " \
          "WHERE inventory_tags.inventory_id = inventories.id " \
          "AND to_tsvector('simple', coalesce(tags.name, '')) @@ to_tsquery('simple', :tsq)" \
        ") " \
        "OR EXISTS (" \
          "SELECT 1 FROM comments " \
          "WHERE comments.inventory_id = inventories.id " \
          "AND to_tsvector('simple', coalesce(comments.body, '')) @@ to_tsquery('simple', :tsq)" \
        ")",
        tsq: tsq
      )
    else
      where(
        "to_tsvector('simple', coalesce(inventories.title, '') || ' ' || coalesce(inventories.description, '')) @@ plainto_tsquery('simple', :q)",
        q: q
      )
    end
  }

  def manageable_by?(user)
    return false unless user

    user.admin? || creator_id == user.id
  end

  def writable_by?(user)
    return false unless user
    return true if manageable_by?(user) || is_public?

    inventory_accesses.exists?(user_id: user.id)
  end

  def tag_list
    return @pending_tag_names.join(", ") if defined?(@pending_tag_names) && !@pending_tag_names.nil?

    tags.map(&:name).join(", ")
  end

  def tag_list=(raw_string)
    names = raw_string.to_s.split(",").map { |n| n.strip.downcase }.reject(&:blank?).uniq
    @pending_tag_names = names

    if persisted? && names.sort != tags.pluck(:name).sort
      updated_at_will_change!
    end
  end

  def ordered_custom_fields
    if custom_fields.loaded?
      custom_fields.reject(&:marked_for_destruction?).sort_by { |cf| [ cf.position.to_i, cf.id.to_i ] }
    else
      custom_fields.to_a
    end
  end

  def dynamic_table_fields
    ordered_custom_fields.select(&:show_in_table?)
  end

  def sync_custom_fields_params!(entries)
    existing_records = custom_fields.to_a
    existing_by_id   = existing_records.index_by(&:id)
    kept_ids         = Set.new
    bool_caster      = ActiveModel::Type::Boolean.new
    @cleared_legacy_slots = Set.new

    Array(entries).each_with_index do |raw, idx|
      data = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
      field_id = data["id"].to_s.strip
      existing = field_id.match?(/\A\d+\z/) ? existing_by_id[field_id.to_i] : nil

      if bool_caster.cast(data["_destroy"])
        if existing
          @cleared_legacy_slots.add(existing.legacy_slot_key) if existing.legacy_slot_key.present?
          existing.mark_for_destruction
        end
        next
      end

      ftype = data["field_type"].to_s.strip.downcase
      next unless CustomField::FIELD_TYPES.key?(ftype)

      record = existing || custom_fields.build
      if existing && existing.field_type != ftype && existing.legacy_slot_key.present?
        @cleared_legacy_slots.add(existing.legacy_slot_key)
        record.legacy_slot_key = nil
      end

      raw_name = data["name"].to_s.strip
      fallback_name = "#{CustomField::FIELD_TYPES[ftype]} ##{idx + 1}"

      record.assign_attributes(
        field_type:     ftype,
        name:           raw_name.presence || fallback_name,
        description:    data["description"].to_s.strip,
        show_in_table:  bool_caster.cast(data["show_in_table"]) == true,
        position:       data["position"].presence ? data["position"].to_i : (idx + 1),
        min_length:     parse_optional_integer(data["min_length"]),
        max_length:     parse_optional_integer(data["max_length"]),
        regex_pattern:  data["regex_pattern"].to_s.strip.presence,
        min_value:      parse_optional_decimal(data["min_value"]),
        max_value:      parse_optional_decimal(data["max_value"]),
        select_options: data["select_options"].to_s.presence
      )

      kept_ids.add(record.id) if record.persisted?
    end

    existing_records.each do |record|
      next if kept_ids.include?(record.id)

      @cleared_legacy_slots.add(record.legacy_slot_key) if record.legacy_slot_key.present?
      record.mark_for_destruction
    end

    mirror_dynamic_fields_to_legacy_columns!
    updated_at_will_change! if persisted?
  end

  def all_custom_field_slots
    slots = []
    FIELD_TYPES.each do |type_key, meta|
      (1..meta[:count]).each do |idx|
        prefix = "#{meta[:prefix]}#{idx}"
        slots << {
          key:           "#{type_key}#{idx}",
          type:          type_key,
          type_label:    meta[:label],
          index:         idx,
          prefix:        prefix,
          value_column:  "#{prefix}_val",
          state:         public_send("#{prefix}_state") == true,
          name:          public_send("#{prefix}_name").to_s,
          description:   public_send("#{prefix}_desc").to_s,
          show_in_table: public_send("#{prefix}_show_in_table") == true,
          position:      public_send("#{prefix}_position").to_i
        }
      end
    end
    slots.sort_by { |s| [ s[:state] ? 0 : 1, s[:position], s[:index] ] }
  end

  def active_custom_fields
    all_custom_field_slots.select { |slot| slot[:state] && slot[:name].present? }
  end

  def table_custom_fields
    active_custom_fields.select { |slot| slot[:show_in_table] }
  end

  def apply_custom_fields_params!(fields_params)
    return if fields_params.blank?

    FIELD_TYPES.each do |type_key, meta|
      (1..meta[:count]).each do |idx|
        slot_key = "#{type_key}#{idx}"
        data = fields_params[slot_key]
        next unless data

        prefix = "#{meta[:prefix]}#{idx}"
        is_active  = ActiveModel::Type::Boolean.new.cast(data[:state])
        raw_name   = data[:name].to_s.strip
        final_name = is_active && raw_name.blank? ? "#{meta[:label]} ##{idx}" : raw_name

        public_send("#{prefix}_state=", is_active)
        public_send("#{prefix}_name=", final_name)
        public_send("#{prefix}_desc=", data[:desc].to_s.strip)
        public_send("#{prefix}_show_in_table=", ActiveModel::Type::Boolean.new.cast(data[:show_in_table]))
        public_send("#{prefix}_position=", data[:position].to_i)
      end
    end

    sync_legacy_slots_to_custom_fields!
    updated_at_will_change! if persisted?
  end

  def statistics
    fields = ordered_custom_fields
    numeric_fields   = fields.select(&:numeric?)
    text_stat_fields = fields.select { |f| f.field_type == "string" || f.field_type == "select" }

    numeric_agg = {}
    if numeric_fields.any?
      ItemFieldValue.where(custom_field_id: numeric_fields.map(&:id))
                    .where.not(numeric_value: nil)
                    .group(:custom_field_id)
                    .pluck(
                      :custom_field_id,
                      Arel.sql("AVG(numeric_value)"),
                      Arel.sql("MIN(numeric_value)"),
                      Arel.sql("MAX(numeric_value)")
                    ).each do |cf_id, avg_val, min_val, max_val|
                      numeric_agg[cf_id] = {
                        avg: avg_val ? avg_val.to_f.round(2) : "—",
                        min: min_val.nil? ? "—" : min_val,
                        max: max_val.nil? ? "—" : max_val
                      }
                    end
    end

    numeric_stats = numeric_fields.map do |field|
      agg = numeric_agg[field.id] || { avg: "—", min: "—", max: "—" }
      { name: field.name, avg: agg[:avg], min: agg[:min], max: agg[:max] }
    end

    grouped_strings = Hash.new { |h, k| h[k] = [] }
    if text_stat_fields.any?
      ItemFieldValue.where(custom_field_id: text_stat_fields.map(&:id))
                    .where.not(string_value: [ nil, "" ])
                    .group(:custom_field_id, :string_value)
                    .count
                    .each do |(cf_id, val), count|
                      grouped_strings[cf_id] << [ val, count ]
                    end
    end

    string_stats = text_stat_fields.map do |field|
      top_vals = grouped_strings[field.id].sort_by { |val, count| [ -count, val.to_s.downcase ] }.first(5)
      { name: field.name, top_values: top_vals }
    end

    {
      total_items: items_count,
      total_likes: items.sum(:likes_count),
      numeric:     numeric_stats,
      strings:     string_stats
    }
  end

  private

  def validate_dynamic_custom_fields
    custom_fields.each do |cf|
      next if cf.marked_for_destruction?
      next if cf.valid?

      label = cf.name.presence || cf.display_type_label
      cf.errors.full_messages.each do |msg|
        errors.add(:base, "#{label}: #{msg}")
      end
    end
  end

  def parse_optional_integer(val)
    str = val.to_s.strip
    return nil if str.blank?

    Integer(str, 10)
  rescue ArgumentError
    str
  end

  def parse_optional_decimal(val)
    str = val.to_s.strip
    return nil if str.blank?

    BigDecimal(str)
  rescue ArgumentError
    str
  end

  def sync_legacy_slots_to_custom_fields!
    existing_by_slot = custom_fields.to_a.select { |cf| cf.legacy_slot_key.present? }.index_by(&:legacy_slot_key)
    @cleared_legacy_slots = Set.new

    FIELD_TYPES.each do |type_key, meta|
      (1..meta[:count]).each do |idx|
        slot_key = "#{type_key}#{idx}"
        prefix   = "#{meta[:prefix]}#{idx}"
        active   = public_send("#{prefix}_state") == true
        cf       = existing_by_slot[slot_key]

        if active
          cf ||= custom_fields.build(legacy_slot_key: slot_key)
          cf.assign_attributes(
            field_type:    type_key,
            name:          public_send("#{prefix}_name").to_s.strip.presence || "#{meta[:label]} ##{idx}",
            description:   public_send("#{prefix}_desc").to_s.strip,
            show_in_table: public_send("#{prefix}_show_in_table") == true,
            position:      public_send("#{prefix}_position").to_i
          )
        elsif cf
          @cleared_legacy_slots.add(cf.legacy_slot_key) if cf.legacy_slot_key.present?
          cf.mark_for_destruction
        end
      end
    end
  end

  def mirror_dynamic_fields_to_legacy_columns!
    FIELD_TYPES.each do |type_key, meta|
      (1..meta[:count]).each do |idx|
        prefix = "#{meta[:prefix]}#{idx}"
        public_send("#{prefix}_state=", false)
      end
    end

    counters = Hash.new(0)
    ordered_custom_fields.each do |cf|
      meta = FIELD_TYPES[cf.field_type]
      next unless meta

      counters[cf.field_type] += 1
      idx = counters[cf.field_type]
      next if idx > meta[:count]

      prefix = "#{meta[:prefix]}#{idx}"
      public_send("#{prefix}_state=", true)
      public_send("#{prefix}_name=", cf.name)
      public_send("#{prefix}_desc=", cf.description)
      public_send("#{prefix}_show_in_table=", cf.show_in_table?)
      public_send("#{prefix}_position=", cf.position)
    end
  end

  def clear_removed_legacy_item_columns
    return unless defined?(@cleared_legacy_slots) && @cleared_legacy_slots.present?

    slots = @cleared_legacy_slots.to_a
    @cleared_legacy_slots = nil

    updates = slots.each_with_object({}) do |slot_key, hash|
      col = Item::LEGACY_VALUE_COLUMNS[slot_key]
      next unless col

      hash[col] = slot_key.start_with?("bool") ? false : nil
    end

    items.update_all(updates) if updates.any?
  end

  def persist_pending_tags
    return unless defined?(@pending_tag_names) && !@pending_tag_names.nil?

    names = @pending_tag_names
    @pending_tag_names = nil

    if names.empty?
      self.tags = []
      return
    end

    existing_names = Tag.where(name: names).pluck(:name)
    missing_names  = names - existing_names
    if missing_names.any?
      now = Time.current
      Tag.insert_all(
        missing_names.map { |name| { name: name, inventories_count: 0, created_at: now, updated_at: now } },
        unique_by: :name
      )
    end

    self.tags = Tag.where(name: names).to_a
  end

  def set_default_custom_id_config
    return if custom_id_config.present?

    self.custom_id_config = [
      { "type" => "fixed",    "value" => "ITEM-", "format" => "" },
      { "type" => "sequence", "value" => "",      "format" => "D4" }
    ]
  end
end
