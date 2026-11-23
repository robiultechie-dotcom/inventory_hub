# frozen_string_literal: true

require "bigdecimal"

class ItemFieldValue < ApplicationRecord
  MAX_NUMERIC_ABS = BigDecimal("99999999999.9999")

  belongs_to :item
  belongs_to :custom_field

  validates :custom_field_id, uniqueness: { scope: :item_id }
  validate :custom_field_belongs_to_item_inventory
  validate :validate_against_custom_field_rules

  def typed_value
    return nil unless custom_field

    case custom_field.field_type
    when "string", "link", "select"
      string_value
    when "text"
      text_value
    when "int"
      numeric_value
    when "bool"
      boolean_value == true
    end
  end

  def assign_raw_value(raw)
    return unless custom_field

    self.string_value  = nil
    self.text_value    = nil
    self.numeric_value = nil
    self.boolean_value = nil
    @invalid_numeric_input = false

    case custom_field.field_type
    when "string", "link", "select"
      self.string_value = raw.to_s.strip.presence
    when "text"
      self.text_value = raw.to_s.presence
    when "int"
      cleaned = raw.to_s.strip
      return if cleaned.blank?

      begin
        self.numeric_value = BigDecimal(cleaned)
      rescue ArgumentError
        @invalid_numeric_input = true
      end
    when "bool"
      self.boolean_value = ActiveModel::Type::Boolean.new.cast(raw) == true
    end
  end

  private

  def custom_field_belongs_to_item_inventory
    return if item.nil? || custom_field.nil?
    return if item.inventory_id == custom_field.inventory_id

    errors.add(:custom_field_id, "must belong to the same inventory as the item")
  end

  def validate_against_custom_field_rules
    return unless custom_field

    case custom_field.field_type
    when "string"
      validate_text_rules(string_value, max_cap: 255, single_line: true)
    when "text"
      validate_text_rules(text_value, max_cap: 10_000, single_line: false)
    when "int"
      validate_numeric_rules
    when "link"
      validate_link_rules
    when "select"
      validate_select_rules
    end
  end

  def validate_text_rules(val, max_cap:, single_line:)
    return if val.blank?

    if single_line && val.match?(/[\r\n]/)
      errors.add(:base, I18n.t("activerecord.errors.models.item.messages.single_line_only", default: "cannot contain line breaks"))
    end

    if val.length > max_cap
      errors.add(:base, I18n.t("items.too_long", count: max_cap, default: "is too long (maximum is #{max_cap} characters)"))
    end

    if custom_field.min_length.present? && val.length < custom_field.min_length
      errors.add(:base, I18n.t("items.too_short", count: custom_field.min_length, default: "must be at least #{custom_field.min_length} characters"))
    end

    if custom_field.max_length.present? && val.length > custom_field.max_length
      errors.add(:base, I18n.t("items.too_long", count: custom_field.max_length, default: "must be at most #{custom_field.max_length} characters"))
    end

    return if custom_field.regex_pattern.blank?

    begin
      unless custom_field.compiled_regex.match?(val)
        errors.add(:base, I18n.t("items.regex_mismatch", pattern: custom_field.regex_pattern, default: "does not match required pattern (#{custom_field.regex_pattern})"))
      end
    rescue Regexp::TimeoutError, RegexpError
      errors.add(:base, I18n.t("items.regex_mismatch", pattern: custom_field.regex_pattern, default: "does not match required pattern"))
    end
  end

  def validate_numeric_rules
    if @invalid_numeric_input
      errors.add(:base, I18n.t("items.invalid_number", default: "must be a valid number"))
      return
    end

    return if numeric_value.nil?

    if numeric_value.abs > MAX_NUMERIC_ABS
      errors.add(:base, I18n.t("items.number_out_of_range", default: "is outside the supported numeric range"))
      return
    end

    if custom_field.min_value.present? && numeric_value < custom_field.min_value
      errors.add(:base, I18n.t("items.below_min_value", min: custom_field.min_value, default: "must be greater than or equal to #{custom_field.min_value}"))
    end

    if custom_field.max_value.present? && numeric_value > custom_field.max_value
      errors.add(:base, I18n.t("items.above_max_value", max: custom_field.max_value, default: "must be less than or equal to #{custom_field.max_value}"))
    end
  end

  def validate_link_rules
    return if string_value.blank?
    return if string_value.match?(/\Ahttps?:\/\/\S+\z/i)

    errors.add(:base, I18n.t("items.invalid_link_url", default: "must be a valid http:// or https:// URL"))
  end

  def validate_select_rules
    return if string_value.blank?

    allowed = custom_field.parsed_select_options
    return if allowed.include?(string_value)

    errors.add(:base, I18n.t("items.invalid_select_option", options: allowed.join(", "), default: "must be one of: #{allowed.join(', ')}"))
  end
end
