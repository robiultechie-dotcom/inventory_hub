# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"

class BrevoApiDelivery
  ENDPOINT = URI.parse("https://api.brevo.com/v3/smtp/email").freeze

  def initialize(settings = {})
    @settings = settings || {}
  end

  def deliver!(mail)
    api_key = (@settings[:api_key].presence || ENV["BREVO_API_KEY"]).to_s.strip
    raise StandardError, "BREVO_API_KEY is not configured." if api_key.blank?

    sender_email = Array(mail.from).first.to_s.strip
    raise StandardError, "Sender email (MAILER_FROM or SMTP_USERNAME) is missing." if sender_email.blank?

    recipients = Array(mail.to).map { |addr| { email: addr.to_s.strip } }.reject { |r| r[:email].blank? }
    raise StandardError, "Recipient email is missing." if recipients.empty?

    raw_html  = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded
    html_body = raw_html.to_s.encode("UTF-8", invalid: :replace, undef: :replace)

    payload = {
      sender:      { name: "InventoryHub", email: sender_email },
      to:          recipients,
      subject:     mail.subject.to_s,
      htmlContent: html_body
    }

    response = post_json(payload, api_key: api_key)
    return response if response.is_a?(Net::HTTPSuccess)

    raise StandardError, "Brevo API error (#{response.code}): #{response.body}"
  end

  private

  def post_json(payload, api_key:)
    execute_request(payload, api_key: api_key, verify_ssl: true)
  rescue OpenSSL::SSL::SSLError
    raise if Rails.env.production?

    execute_request(payload, api_key: api_key, verify_ssl: false)
  end

  def execute_request(payload, api_key:, verify_ssl:)
    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    if verify_ssl
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.cert_store = store
    else
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Post.new(ENDPOINT.request_uri)
    request["api-key"] = api_key
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(payload)

    http.request(request)
  end
end