# frozen_string_literal: true

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

  before_create :set_default_custom_id_config
  after_save :persist_pending_tags

  scope :latest_first, -> { includes(:category, :creator, :tags).order(created_at: :desc) }
  scope :top_popular, ->(limit_count = 5) { includes(:category, :creator).order(items_count: :desc, created_at: :desc).limit(limit_count) }

  def self.build_fts_query(query)
    tokens = query.to_s.scan(/[[:alnum:]]+/).map(&:downcase).reject(&:blank?).first(8)
    return nil if tokens.empty?

    tokens.map { |token| "#{token}:*" }.join(" & ")
  end

  # Section 14: Native PostgreSQL GIN-indexed full-text search across title, description, tags & comments
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

  # Deferred bulk tag assignment so failed validations or lock conflicts never mutate DB tags
  def tag_list=(raw_string)
    names = raw_string.to_s.split(",").map { |n| n.strip.downcase }.reject(&:blank?).uniq
    @pending_tag_names = names

    if persisted? && names.sort != tags.pluck(:name).sort
      updated_at_will_change!
    end
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
        is_active = ActiveModel::Type::Boolean.new.cast(data[:state])
        raw_name  = data[:name].to_s.strip
        final_name = is_active && raw_name.blank? ? "#{meta[:label]} ##{idx}" : raw_name

        public_send("#{prefix}_state=", is_active)
        public_send("#{prefix}_name=", final_name)
        public_send("#{prefix}_desc=", data[:desc].to_s.strip)
        public_send("#{prefix}_show_in_table=", ActiveModel::Type::Boolean.new.cast(data[:show_in_table]))
        public_send("#{prefix}_position=", data[:position].to_i)
      end
    end
  end

  def statistics
    numeric_fields = active_custom_fields.select { |f| f[:type] == "int" }
    numeric_stats = if numeric_fields.any?
                      select_exprs = numeric_fields.flat_map do |f|
                        col = self.class.connection.quote_column_name(f[:value_column])
                        [ "AVG(#{col})", "MIN(#{col})", "MAX(#{col})" ]
                      end
                      row = items.pick(*select_exprs.map { |e| Arel.sql(e) })
                      row = Array(row)
                      numeric_fields.each_with_index.map do |f, idx|
                        avg_val, min_val, max_val = row[idx * 3, 3]
                        {
                          name: f[:name],
                          avg:  avg_val ? avg_val.to_f.round(2) : "—",
                          min:  min_val.nil? ? "—" : min_val,
                          max:  max_val.nil? ? "—" : max_val
                        }
                      end
    else
                      []
    end

    string_stats = active_custom_fields.select { |f| f[:type] == "string" }.map do |field|
      col = field[:value_column]
      top_vals = items.where.not(col => [ nil, "" ])
                      .group(col)
                      .order(Arel.sql("COUNT(*) DESC"))
                      .limit(5)
                      .count
                      .to_a
      {
        name:       field[:name],
        top_values: top_vals
      }
    end

    {
      total_items: items_count,
      total_likes: items.sum(:likes_count),
      numeric:     numeric_stats,
      strings:     string_stats
    }
  end

  private

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