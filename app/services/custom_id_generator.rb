# frozen_string_literal: true

require "securerandom"

class CustomIdGenerator
  SUPPORTED_ELEMENTS = {
    "fixed"         => "Fixed text",
    "random_20bit"  => "20-bit random",
    "random_32bit"  => "32-bit random",
    "random_6digit" => "6-digit random",
    "random_9digit" => "9-digit random",
    "guid"          => "GUID",
    "datetime"      => "Date/time",
    "sequence"      => "Sequence"
  }.freeze

  MAX_20BIT = (1 << 20) - 1
  MAX_32BIT = (1 << 32) - 1

  def initialize(inventory)
    @inventory = inventory
    @elements = normalize_elements(inventory&.custom_id_config)
  end

  def generate(preview: false, static_preview: false, timestamp: Time.current)
    seq_num = if static_preview
                (@inventory&.items_count.to_i + 1)
              elsif preview
                preview_sequence_number
              else
                next_sequence_number
              end

    return format("ITEM-%04d", seq_num) if @elements.empty?

    @elements.map { |el| render_element(el, seq_num: seq_num, preview: preview || static_preview, timestamp: timestamp) }.join
  end

  def valid_format?(candidate_id)
    return false if candidate_id.blank?
    return true if @elements.empty?

    pattern = @elements.map { |el| element_regex_fragment(el) }.join
    Regexp.new("\\A#{pattern}\\z").match?(candidate_id.to_s)
  end

  # Section 6: Sequence equals the largest existing sequence number + 1 at the moment of item creation
  def next_sequence_number
    return 1 unless @inventory&.persisted?

    existing_ids = @inventory.items.pluck(:custom_id)
    return 1 if existing_ids.empty?

    seq_regex = build_sequence_extraction_regex
    if seq_regex
      matched_sequences = existing_ids.filter_map do |cid|
        m = seq_regex.match(cid.to_s)
        m[:seq].to_i if m && m.names.include?("seq")
      end
      return matched_sequences.max + 1 if matched_sequences.any?
    end

    # Fallback across format changes: check legacy ITEM-0001 or trailing sequence tokens
    legacy_sequences = existing_ids.filter_map do |cid|
      str = cid.to_s
      if (m = str.match(/\AITEM-(\d+)\z/))
        m[1].to_i
      elsif (m = str.match(/(?:^|[-_])(\d{1,6})\z/))
        val = m[1].to_i
        val unless (2020..2035).cover?(val) && m[1].length == 4
      end
    end

    return legacy_sequences.max + 1 if legacy_sequences.any?

    existing_ids.size + 1
  end

  private

  def normalize_elements(raw_config)
    Array(raw_config).filter_map do |entry|
      next unless entry.is_a?(Hash)

      type = entry["type"].to_s
      next unless SUPPORTED_ELEMENTS.key?(type)

      spec = entry["format"].presence || entry["value"].to_s
      { "type" => type, "spec" => spec }
    end.first(10)
  end

  def render_element(element, seq_num:, preview:, timestamp:)
    type = element["type"]
    spec = element["spec"].to_s

    case type
    when "fixed"
      spec
    when "random_20bit"
      val = preview ? 687_674 : SecureRandom.random_number(MAX_20BIT + 1)
      format_number_with_affixes(val, spec, "X5")
    when "random_32bit"
      val = preview ? 3_880_747_817 : SecureRandom.random_number(MAX_32BIT + 1)
      format_number_with_affixes(val, spec, "X8")
    when "random_6digit"
      val = preview ? 482_910 : SecureRandom.random_number(1_000_000)
      format_number_with_affixes(val, spec, "D6")
    when "random_9digit"
      val = preview ? 739_201_845 : SecureRandom.random_number(1_000_000_000)
      format_number_with_affixes(val, spec, "D9")
    when "guid"
      preview ? "550e8400-e29b-41d4-a716-446655440000" : SecureRandom.uuid
    when "datetime"
      format_datetime(timestamp, spec.presence || "yyyy")
    when "sequence"
      format_number_with_affixes(seq_num, spec, "D3")
    else
      ""
    end
  end

  def format_number_with_affixes(number, spec, default_code)
    raw = spec.strip.presence || default_code
    match = raw.match(/\A([^DXdx]*)([DXdx]\d*)(.*)\z/)
    return number.to_s unless match

    prefix, code, suffix = match.captures
    digits = code[1..].to_i
    base   = code.downcase.start_with?("x") ? 16 : 10
    core   = number.to_i.to_s(base)
    core   = core.rjust(digits, "0") if digits.positive?
    core   = code.start_with?("X") ? core.upcase : core.downcase
    "#{prefix}#{core}#{suffix}"
  end

  def format_datetime(time, spec)
    spec.dup
        .gsub("yyyy", time.strftime("%Y"))
        .gsub("yy",   time.strftime("%y"))
        .gsub("MM",   time.strftime("%m"))
        .gsub("ddd",  time.strftime("%a"))
        .gsub("dd",   time.strftime("%d"))
        .gsub("HH",   time.strftime("%H"))
        .gsub("mm",   time.strftime("%M"))
        .gsub("ss",   time.strftime("%S"))
  end

  def preview_sequence_number
    return 1 unless @inventory&.persisted?

    next_sequence_number
  end

  def build_sequence_extraction_regex
    return nil unless @elements.any? { |el| el["type"] == "sequence" }

    captured = false
    pattern = @elements.map do |el|
      if el["type"] == "sequence" && !captured
        captured = true
        sequence_capture_fragment(el["spec"].to_s)
      else
        element_regex_fragment(el)
      end
    end.join

    Regexp.new("\\A#{pattern}\\z")
  rescue RegexpError
    nil
  end

  def sequence_capture_fragment(spec)
    raw = spec.strip.presence || "D3"
    match = raw.match(/\A([^DXdx]*)([DXdx]\d*)(.*)\z/)
    return "(?<seq>\\d+)" unless match

    prefix, _code, suffix = match.captures
    "#{Regexp.escape(prefix)}(?<seq>\\d+)#{Regexp.escape(suffix)}"
  end

  def element_regex_fragment(element)
    type = element["type"]
    spec = element["spec"].to_s

    case type
    when "fixed"
      Regexp.escape(spec)
    when "random_20bit"
      numeric_regex_fragment(spec, "X5")
    when "random_32bit"
      numeric_regex_fragment(spec, "X8")
    when "random_6digit"
      numeric_regex_fragment(spec, "D6")
    when "random_9digit"
      numeric_regex_fragment(spec, "D9")
    when "guid"
      "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    when "datetime"
      datetime_regex_fragment(spec.presence || "yyyy")
    when "sequence"
      numeric_regex_fragment(spec, "D3", allow_wider: true)
    else
      ".*"
    end
  end

  def numeric_regex_fragment(spec, default_code, allow_wider: false)
    raw = spec.strip.presence || default_code
    match = raw.match(/\A([^DXdx]*)([DXdx]\d*)(.*)\z/)
    return "\\d+" unless match

    prefix, code, suffix = match.captures
    digits = code[1..].to_i
    char_class = code.downcase.start_with?("x") ? "[0-9a-fA-F]" : "\\d"
    quantifier = if digits.positive?
                   allow_wider ? "{#{digits},}" : "{#{digits}}"
                 else
                   "+"
                 end

    "#{Regexp.escape(prefix)}#{char_class}#{quantifier}#{Regexp.escape(suffix)}"
  end

  def datetime_regex_fragment(spec)
    escaped = Regexp.escape(spec)
    escaped.gsub("yyyy", "\\d{4}")
           .gsub("yy",   "\\d{2}")
           .gsub("MM",   "\\d{2}")
           .gsub("ddd",  "[A-Za-z]{3}")
           .gsub("dd",   "\\d{2}")
           .gsub("HH",   "\\d{2}")
           .gsub("mm",   "\\d{2}")
           .gsub("ss",   "\\d{2}")
  end
end