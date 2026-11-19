# frozen_string_literal: true

class Item < ApplicationRecord
  self.locking_column = :lock_version

  SINGLE_LINE_COLUMNS = %i[custom_string1_val custom_string2_val custom_string3_val].freeze
  MULTI_LINE_COLUMNS  = %i[custom_text1_val custom_text2_val custom_text3_val].freeze

  belongs_to :inventory, counter_cache: true
  belongs_to :created_by, class_name: "User", inverse_of: :created_items
  has_many :likes, dependent: :destroy

  before_validation :assign_generated_custom_id, on: :create

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

  scope :full_text_search, lambda { |query|
    q = query.to_s.strip
    return none if q.blank?

    sanitized_like = "%#{sanitize_sql_like(q)}%"
    searchable_expr = [
      "coalesce(items.custom_id, '')",
      "coalesce(items.custom_string1_val, '')",
      "coalesce(items.custom_string2_val, '')",
      "coalesce(items.custom_string3_val, '')",
      "coalesce(items.custom_text1_val, '')",
      "coalesce(items.custom_text2_val, '')",
      "coalesce(items.custom_text3_val, '')"
    ].join(" || ' ' || ")

    where(
      "to_tsvector('simple', #{searchable_expr}) @@ plainto_tsquery('simple', :q) " \
      "OR items.custom_id ILIKE :like " \
      "OR items.custom_string1_val ILIKE :like " \
      "OR items.custom_string2_val ILIKE :like " \
      "OR items.custom_string3_val ILIKE :like " \
      "OR items.custom_text1_val ILIKE :like",
      q: q,
      like: sanitized_like
    )
  }

  def primary_label
    first_string = inventory.active_custom_fields.find { |f| f[:type] == "string" }
    val = first_string ? public_send(first_string[:value_column]) : nil
    val.presence || custom_id
  end

  def search_index_text
    values = inventory.table_custom_fields.map { |f| public_send(f[:value_column]).to_s }
    [custom_id, created_by&.name, *values].compact.join(" ").downcase
  end

  private

  def assign_generated_custom_id
    return if custom_id.present? || inventory.blank?

    self.custom_id = CustomIdGenerator.new(inventory).generate(preview: false)
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

    inventory.active_custom_fields.select { |f| f[:type] == "link" }.each do |field|
      val = public_send(field[:value_column]).to_s.strip
      next if val.blank?

      unless val.match?(/\Ahttps?:\/\/\S+\z/i)
        errors.add(:base, "#{field[:name]}: #{I18n.t('items.invalid_link_url', default: 'must be a valid http:// or https:// URL')}")
      end
    end
  end
end