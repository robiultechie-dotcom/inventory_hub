# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"

class GoogleAppsScriptDelivery
  MAX_REDIRECTS = 5

  def initialize(settings = {})
    @settings = settings || {}
  end

  def deliver!(mail)
    webhook_url = (@settings[:webhook_url].presence || ENV["GOOGLE_MAILER_URL"]).to_s.strip
    secret = (@settings[:secret].presence || ENV["GOOGLE_MAILER_SECRET"]).to_s.strip

    raise StandardError, "GOOGLE_MAILER_URL is not configured." if webhook_url.blank?
    raise StandardError, "GOOGLE_MAILER_SECRET is not configured." if secret.blank?

    recipients = Array(mail.to).map { |addr| addr.to_s.strip }.reject(&:blank?)
    raise StandardError, "Recipient email is missing." if recipients.empty?

    raw_html = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded
    html_body = raw_html.to_s.encode("UTF-8", invalid: :replace, undef: :replace)

    payload = {
      token: secret,
      to: recipients.join(","),
      subject: mail.subject.to_s,
      html: html_body,
      senderName: "InventoryHub"
    }

    response = post_with_redirects(webhook_url, payload)
    parse_and_verify!(response)
  end

  private

  def post_with_redirects(url, payload)
    uri = parse_https_uri!(url)
    response = execute_request(uri, :post, JSON.generate(payload))

    redirects = 0
    while response.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS
      location = response["location"].to_s.strip
      raise StandardError, "Google Apps Script redirect missing Location header." if location.blank?

      redirect_uri = parse_https_uri!(location)
      response = execute_request(redirect_uri, :get)
      redirects += 1
    end

    response
  end

  def parse_https_uri!(raw_url)
    uri = URI.parse(raw_url)
    unless uri.is_a?(URI::HTTPS) && uri.host.present?
      raise StandardError, "Invalid HTTPS URL for Google Apps Script mailer."
    end

    uri
  rescue URI::InvalidURIError
    raise StandardError, "Invalid URL format for Google Apps Script mailer."
  end

  def execute_request(uri, method, json_body = nil)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 20

    store = OpenSSL::X509::Store.new
    store.set_default_paths
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = store

    request =
      if method == :post
        req = Net::HTTP::Post.new(uri.request_uri)
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json"
        req.body = json_body
        req
      else
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Accept"] = "application/json"
        req
      end

    http.request(request)
  end

  def parse_and_verify!(response)
    unless response.is_a?(Net::HTTPSuccess)
      raise StandardError, "Google Apps Script HTTP error (#{response.code}): #{response.body.to_s[0, 200]}"
    end

    data = JSON.parse(response.body.to_s)
    return response if data["ok"] == true

    raise StandardError, "Google Apps Script error: #{data['error'] || 'Unknown error'}"
  rescue JSON::ParserError
    raise StandardError, "Google Apps Script returned non-JSON response (HTTP #{response.code}). Ensure Web App access is set to Anyone."
  end
end
