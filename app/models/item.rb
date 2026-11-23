# frozen_string_literal: true

class Item < ApplicationRecord
  self.locking_column = :lock_version

  SINGLE_LINE_COLUMNS = %i[custom_string1_val custom_string2_val custom_string3_val].freeze
  MULTI_LINE_COLUMNS  = %i[custom_text1_val custom_text2_val custom_text3_val].freeze

  LEGACY_VALUE_COLUMNS = {
    "string1" => :custom_string1_val, "string2" => :custom_string2_val, "string3" => :custom_string3_val,
    "text1"   => :custom_text1_val,   "text2"   => :custom_text2_val,   "text3"   => :custom_text3_val,
    "int1"    => :custom_int1_val,    "int2"    => :custom_int2_val,    "int3"    => :custom_int3_val,
    "link1"   => :custom_link1_val,   "link2"   => :custom_link2_val,   "link3"   => :custom_link3_val,
    "bool1"   => :custom_bool1_val,   "bool2"   => :custom_bool2_val,   "bool3"   => :custom_bool3_val
  }.freeze

  belongs_to :inventory, counter_cache: true
  belongs_to :created_by, class_name: "User", inverse_of: :created_items
  has_many :item_field_values, dependent: :destroy, autosave: true, validate: false
  has_many :likes, dependent: :destroy

  before_validation :assign_generated_custom_id, on: :create
  before_validation :sync_legacy_columns_to_dynamic_values

  validates :custom_id,
            presence: true,
            length: { maximum: 120 },
            uniqueness: {
              scope: :inventory_id,
              message: :taken
            }

  validates(*SINGLE_LINE_COLUMNS, length: { maximum: 255 }, format: { without: /[\r\n]/, message: :single_line_only }, allow_blank: true)
  validates(*MULTI_LINE_COLUMNS, length: { maximum: 10_000 }, allow_blank: true)

  validate :enforce_custom_id_format
  validate :validate_custom_link_fields
  validate :validate_dynamic_field_values

  def self.build_fts_query(query)
    tokens = query.to_s.scan(/[[:alnum:]]+/).map(&:downcase).reject(&:blank?).first(8)
    return nil if tokens.empty?

    tokens.map { |token| "#{token}:*" }.join(" & ")
  end

  # Section 14: Native PostgreSQL GIN-indexed full-text search across item IDs & field values
  scope :full_text_search, lambda { |query|
    q = query.to_s.strip
    return none if q.blank?

    searchable_expr = [
      "coalesce(items.custom_id, '')",
      "coalesce(items.custom_string1_val, '')",
      "coalesce(items.custom_string2_val, '')",
      "coalesce(items.custom_string3_val, '')",
      "coalesce(items.custom_text1_val, '')",
      "coalesce(items.custom_text2_val, '')",
      "coalesce(items.custom_text3_val, '')"
    ].join(" || ' ' || ")

    tsq = build_fts_query(q)
    if tsq.present?
      where(
        "to_tsvector('simple', #{searchable_expr}) @@ to_tsquery('simple', :tsq) " \
        "OR EXISTS (" \
          "SELECT 1 FROM item_field_values " \
          "WHERE item_field_values.item_id = items.id " \
          "AND to_tsvector('simple', coalesce(item_field_values.string_value, '') || ' ' || coalesce(item_field_values.text_value, '')) @@ to_tsquery('simple', :tsq)" \
        ")",
        tsq: tsq
      )
    else
      where("to_tsvector('simple', #{searchable_expr}) @@ plainto_tsquery('simple', :q)", q: q)
    end
  }

  # In-memory lookup (zero N+1 queries when item_field_values are preloaded)
  def value_for(custom_field)
    cf_id = custom_field.is_a?(CustomField) ? custom_field.id : custom_field.to_i
    record = item_field_values.detect { |v| v.custom_field_id == cf_id && !v.marked_for_destruction? }
    return record.typed_value if record

    if custom_field.is_a?(CustomField) && custom_field.legacy_slot_key.present?
      legacy_col = LEGACY_VALUE_COLUMNS[custom_field.legacy_slot_key]
      return public_send(legacy_col) if legacy_col && respond_to?(legacy_col)
    end

    custom_field.is_a?(CustomField) && custom_field.boolean? ? false : nil
  end

  def assign_dynamic_field_values(values_hash)
    return if inventory.blank? || values_hash.nil?

    @dynamic_values_assigned = true
    existing_by_cf = item_field_values.to_a.index_by(&:custom_field_id)

    inventory.ordered_custom_fields.each do |cf|
      key = cf.id.to_s
      next unless values_hash.key?(key) || values_hash.key?(cf.id)

      raw = values_hash.key?(key) ? values_hash[key] : values_hash[cf.id]
      record = existing_by_cf[cf.id]

      if !cf.boolean? && raw.to_s.strip.blank?
        record&.mark_for_destruction
        mirror_value_to_legacy_column(cf, nil)
      else
        record ||= item_field_values.build(custom_field: cf)
        record.assign_raw_value(raw)
        mirror_value_to_legacy_column(cf, record.typed_value)
      end
    end

    # Always bump lock_version on save so Optimistic Locking detects concurrent custom field edits
    updated_at_will_change! if persisted?
  end

  def primary_label
    if inventory
      dynamic_fields = inventory.ordered_custom_fields
      if dynamic_fields.any?
        first_label_field = dynamic_fields.find { |f| f.field_type == "string" || f.field_type == "select" }
        val = first_label_field ? value_for(first_label_field) : nil
        return val if val.present?
      else
        first_string = inventory.active_custom_fields.find { |f| f[:type] == "string" }
        val = first_string ? public_send(first_string[:value_column]) : nil
        return val if val.present?
      end
    end

    custom_id
  end

  def search_index_text
    values = if inventory&.ordered_custom_fields&.any?
      inventory.dynamic_table_fields.map { |f| value_for(f).to_s }
    elsif inventory
      inventory.table_custom_fields.map { |f| public_send(f[:value_column]).to_s }
    else
      []
    end
    [ custom_id, created_by&.name, *values ].compact.join(" ").downcase
  end

  private

  def assign_generated_custom_id
    return if custom_id.present? || inventory.blank?

    self.custom_id = CustomIdGenerator.new(inventory).generate(preview: false)
  end

  def mirror_value_to_legacy_column(cf, typed_val)
    return if cf.legacy_slot_key.blank?

    col = LEGACY_VALUE_COLUMNS[cf.legacy_slot_key]
    return unless col && respond_to?("#{col}=")

    val = cf.boolean? ? (typed_val == true) : typed_val
    public_send("#{col}=", val)
  end

  # Keeps vertical item_field_values in sync when legacy form columns are submitted prior to Step 4
  def sync_legacy_columns_to_dynamic_values
    return if @dynamic_values_assigned || inventory.blank?

    dynamic_fields = inventory.ordered_custom_fields.select { |cf| cf.legacy_slot_key.present? }
    return if dynamic_fields.empty?

    existing_by_cf = item_field_values.to_a.index_by(&:custom_field_id)

    dynamic_fields.each do |cf|
      col = LEGACY_VALUE_COLUMNS[cf.legacy_slot_key]
      next unless col && respond_to?(col)

      raw = public_send(col)
      record = existing_by_cf[cf.id]

      if !cf.boolean? && raw.to_s.strip.blank?
        record&.mark_for_destruction
      else
        record ||= item_field_values.build(custom_field: cf)
        record.assign_raw_value(raw)
      end
    end
  end

  def enforce_custom_id_format
    return if custom_id.blank? || inventory.blank?

    generator = CustomIdGenerator.new(inventory)
    return if generator.valid_format?(custom_id)

    example = generator.generate(preview: true)
    errors.add(:custom_id, I18n.t("items.invalid_custom_id_format", example: example, default: "does not match required inventory format (e.g. #{example})"))
  end

  def validate_custom_link_fields
    return unless inventory
    return if @dynamic_values_assigned

    inventory.active_custom_fields.select { |f| f[:type] == "link" }.each do |field|
      val = public_send(field[:value_column]).to_s.strip
      next if val.blank?

      unless val.match?(/\Ahttps?:\/\/\S+\z/i)
        errors.add(:base, "#{field[:name]}: #{I18n.t('items.invalid_link_url', default: 'must be a valid http:// or https:// URL')}")
      end
    end
  end

  def validate_dynamic_field_values
    item_field_values.each do |fv|
      next if fv.marked_for_destruction?
      next if fv.valid?

      cf_name = fv.custom_field&.name || "Field"
      fv.errors.full_messages.each do |msg|
        errors.add(:base, "#{cf_name}: #{msg}")
      end
    end
  end
end
