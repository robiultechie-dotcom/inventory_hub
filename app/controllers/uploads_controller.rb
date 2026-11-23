# frozen_string_literal: true

require "uri"
require "digest/sha1"

class UploadsController < ApplicationController
  before_action :authenticate_user!

  # Issues a short-lived Cloudinary upload signature so the browser uploads
  # directly to Cloudinary CDN without sending image bytes through Rails (Sections 14 & 15).
  def signature
    response.headers["Cache-Control"] = "no-store"

    config    = parse_cloudinary_url!
    timestamp = Time.current.to_i
    sig       = Digest::SHA1.hexdigest("timestamp=#{timestamp}#{config[:api_secret]}")

    render json: {
      cloud_name: config[:cloud_name],
      api_key:    config[:api_key],
      timestamp:  timestamp,
      signature:  sig
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def parse_cloudinary_url!
    raw_url = ENV["CLOUDINARY_URL"].to_s.strip.sub(/\ACLOUDINARY_URL=/i, "")
    if raw_url.blank?
      raise StandardError, t("flashes.upload_not_configured", default: "Cloud image upload service is not configured on the server.")
    end

    uri_cfg    = URI.parse(raw_url)
    cloud_name = uri_cfg.host.to_s.strip
    api_key    = URI::DEFAULT_PARSER.unescape(uri_cfg.user.to_s).strip
    api_secret = URI::DEFAULT_PARSER.unescape(uri_cfg.password.to_s).strip

    unless uri_cfg.scheme == "cloudinary" && cloud_name.present? && api_key.present? && api_secret.present?
      raise StandardError, t("flashes.invalid_cloudinary_url", default: "Invalid CLOUDINARY_URL format.")
    end

    { cloud_name: cloud_name, api_key: api_key, api_secret: api_secret }
  rescue URI::InvalidURIError
    raise StandardError, t("flashes.invalid_cloudinary_url", default: "Invalid CLOUDINARY_URL format.")
  end
end