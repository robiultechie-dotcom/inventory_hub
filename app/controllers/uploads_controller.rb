# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"
require "digest/sha1"

class UploadsController < ApplicationController
  before_action :authenticate_user!

  MAX_FILE_SIZE = 5.megabytes
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/jpg image/png image/webp image/gif].freeze

  def create
    uploaded_file = params[:file]
    validate_uploaded_file!(uploaded_file)

    image_url = upload_to_cloud_stream(uploaded_file)
    render json: { url: image_url }, status: :created
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def validate_uploaded_file!(file)
    unless file.respond_to?(:content_type) && ALLOWED_CONTENT_TYPES.include?(file.content_type.to_s.downcase)
      raise StandardError, t("flashes.invalid_image")
    end

    if file.respond_to?(:size) && file.size > MAX_FILE_SIZE
      raise StandardError, "Image size must be under 5 MB."
    end
  end

  def upload_to_cloud_stream(uploaded_file)
    if ENV["CLOUDINARY_URL"].present?
      stream_to_cloudinary_signed(uploaded_file)
    elsif ENV["CLOUDINARY_CLOUD_NAME"].present? && ENV["CLOUDINARY_UPLOAD_PRESET"].present?
      stream_to_cloudinary_unsigned(uploaded_file)
    elsif ENV["FREEIMAGE_API_KEY"].present?
      stream_to_freeimage(uploaded_file)
    else
      raise StandardError, "Cloud image upload service is not configured on the server."
    end
  end

  def stream_to_cloudinary_signed(uploaded_file)
    raw_url    = ENV.fetch("CLOUDINARY_URL").to_s.strip.sub(/\ACLOUDINARY_URL=/i, "")
    uri_cfg    = URI.parse(raw_url)
    cloud_name = uri_cfg.host.to_s.strip
    api_key    = uri_cfg.user.to_s.strip
    api_secret = uri_cfg.password.to_s.strip

    if cloud_name.blank? || api_key.blank? || api_secret.blank?
      raise StandardError, "Invalid CLOUDINARY_URL format."
    end

    timestamp = Time.current.to_i.to_s
    signature = Digest::SHA1.hexdigest("timestamp=#{timestamp}#{api_secret}")
    endpoint  = URI.parse("https://api.cloudinary.com/v1_1/#{cloud_name}/image/upload")

    File.open(uploaded_file.tempfile.path, "rb") do |file_io|
      multipart_fields = [
        [ "file", file_io, { filename: uploaded_file.original_filename.to_s, content_type: uploaded_file.content_type.to_s } ],
        [ "api_key", api_key ],
        [ "timestamp", timestamp ],
        [ "signature", signature ]
      ]
      response = post_multipart_stream(endpoint, multipart_fields)
      JSON.parse(response.body).fetch("secure_url")
    end
  end

  def stream_to_cloudinary_unsigned(uploaded_file)
    cloud_name = ENV.fetch("CLOUDINARY_CLOUD_NAME").to_s.strip
    preset     = ENV.fetch("CLOUDINARY_UPLOAD_PRESET").to_s.strip
    endpoint   = URI.parse("https://api.cloudinary.com/v1_1/#{cloud_name}/image/upload")

    File.open(uploaded_file.tempfile.path, "rb") do |file_io|
      multipart_fields = [
        [ "file", file_io, { filename: uploaded_file.original_filename.to_s, content_type: uploaded_file.content_type.to_s } ],
        [ "upload_preset", preset ]
      ]
      response = post_multipart_stream(endpoint, multipart_fields)
      JSON.parse(response.body).fetch("secure_url")
    end
  end

  def stream_to_freeimage(uploaded_file)
    endpoint = URI.parse("https://freeimage.host/api/1/upload")

    File.open(uploaded_file.tempfile.path, "rb") do |file_io|
      multipart_fields = [
        [ "key", ENV.fetch("FREEIMAGE_API_KEY").to_s.strip ],
        [ "action", "upload" ],
        [ "format", "json" ],
        [ "source", file_io, { filename: uploaded_file.original_filename.to_s, content_type: uploaded_file.content_type.to_s } ]
      ]
      response = post_multipart_stream(endpoint, multipart_fields)
      JSON.parse(response.body).dig("image", "url") || raise(StandardError, "Cloud upload failed.")
    end
  end

  def post_multipart_stream(uri, multipart_fields)
    response = execute_multipart_post(uri, multipart_fields, verify_ssl: true)
    unless response.is_a?(Net::HTTPSuccess)
      err_detail = (JSON.parse(response.body).dig("error", "message") rescue nil)
      raise StandardError, (err_detail.presence || "Cloud service error (#{response.code})")
    end

    response
  rescue OpenSSL::SSL::SSLError
    raise if Rails.env.production?

    multipart_fields.each { |field| field[1].rewind if field[1].respond_to?(:rewind) }
    response = execute_multipart_post(uri, multipart_fields, verify_ssl: false)
    unless response.is_a?(Net::HTTPSuccess)
      err_detail = (JSON.parse(response.body).dig("error", "message") rescue nil)
      raise StandardError, (err_detail.presence || "Cloud service error (#{response.code})")
    end

    response
  end

  def execute_multipart_post(uri, multipart_fields, verify_ssl:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 25

    if verify_ssl
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.cert_store = store
    else
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form(multipart_fields, "multipart/form-data")
    http.request(request)
  end
end