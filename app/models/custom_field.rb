# frozen_string_literal: true

class CustomField < ApplicationRecord
  FIELD_TYPES = {
    "string" => "Single-Line Text",
    "text"   => "Multi-Line Text",
    "int"    => "Numeric",
    "link"   => "Document/Image",
    "bool"   => "True/False",
    "select" => "One From List"
  }.freeze

  MAX_REGEX_LENGTH   = 120
  MAX_SELECT_OPTIONS = 50
  REGEX_TIMEOUT_SEC  = 0.2

  belongs_to :inventory
  has_many :item_field_values, dependent: :destroy

  before_validation :normalize_attributes

  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES.keys }
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 300 }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validates :min_length, :max_length,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000 },
            allow_nil: true
  validates :min_value, :max_value, numericality: true, allow_nil: true
  validates :regex_pattern, length: { maximum: MAX_REGEX_LENGTH }, allow_blank: true

  validate :validate_length_bounds
  validate :validate_numeric_bounds
  validate :validate_regex_syntax
  validate :validate_select_options_list

  def parsed_select_options
    select_options.to_s.split(/[\r\n,]+/).map(&:strip).reject(&:blank?).uniq
  end

  def compiled_regex
    return nil if regex_pattern.blank?

    Regexp.new(regex_pattern, timeout: REGEX_TIMEOUT_SEC)
  end

  def text_based?
    field_type == "string" || field_type == "text"
  end

  def numeric?
    field_type == "int"
  end

  def boolean?
    field_type == "bool"
  end

  def link?
    field_type == "link"
  end

  def select_list?
    field_type == "select"
  end

  def display_type_label
    I18n.t("inventory.field_slot_labels.#{field_type}", default: FIELD_TYPES[field_type])
  end

  def tuning_hints
    hints = []
    if text_based?
      hints << I18n.t("fields.hint_min_len", value: min_length) if min_length.present?
      hints << I18n.t("fields.hint_max_len", value: max_length) if max_length.present?
      hints << I18n.t("fields.hint_pattern", value: regex_pattern) if regex_pattern.present?
    elsif numeric?
      hints << I18n.t("fields.hint_min", value: format_bound(min_value)) if min_value.present?
      hints << I18n.t("fields.hint_max", value: format_bound(max_value)) if max_value.present?
    end
    hints
  end

  private

  def normalize_attributes
    self.field_type     = field_type.to_s.strip.downcase
    self.name           = name.to_s.strip
    self.description    = description.to_s.strip
    self.regex_pattern  = regex_pattern.to_s.strip.presence
    self.select_options = parsed_select_options.join("\n").presence

    if text_based?
      self.min_value = nil
      self.max_value = nil
      self.select_options = nil
    elsif numeric?
      self.min_length = nil
      self.max_length = nil
      self.regex_pattern = nil
      self.select_options = nil
    elsif select_list?
      self.min_length = nil
      self.max_length = nil
      self.regex_pattern = nil
      self.min_value = nil
      self.max_value = nil
    else
      self.min_length = nil
      self.max_length = nil
      self.regex_pattern = nil
      self.min_value = nil
      self.max_value = nil
      self.select_options = nil
    end
  end

  def validate_length_bounds
    return if min_length.nil? || max_length.nil?
    return if min_length <= max_length

    errors.add(:min_length, I18n.t("fields.min_gt_max"))
  end

  def validate_numeric_bounds
    return if min_value.nil? || max_value.nil?
    return if min_value <= max_value

    errors.add(:min_value, I18n.t("fields.min_gt_max"))
  end

  def validate_regex_syntax
    return if regex_pattern.blank?

    Regexp.new(regex_pattern, timeout: REGEX_TIMEOUT_SEC)
  rescue RegexpError => e
    errors.add(:regex_pattern, I18n.t("fields.invalid_regex", detail: e.message))
  end

  def validate_select_options_list
    return unless select_list?

    opts = parsed_select_options
    if opts.empty?
      errors.add(:select_options, I18n.t("fields.select_options_required"))
    elsif opts.size > MAX_SELECT_OPTIONS
      errors.add(:select_options, I18n.t("fields.select_options_limit", max: MAX_SELECT_OPTIONS))
    elsif opts.any? { |opt| opt.length > 100 }
      errors.add(:select_options, I18n.t("fields.select_option_too_long"))
    end
  end

  def format_bound(num)
    return "" if num.nil?

    num.frac.zero? ? num.to_i.to_s : num.to_s("F").sub(/\.?0+\z/, "")
  end
end
