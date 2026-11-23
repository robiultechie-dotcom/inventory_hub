# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  if ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
    provider :google_oauth2,
             ENV.fetch("GOOGLE_CLIENT_ID").strip,
             ENV.fetch("GOOGLE_CLIENT_SECRET").strip,
             {
               scope: "email,profile",
               prompt: "select_account"
             }
  end

  if ENV["FACEBOOK_APP_ID"].present? && ENV["FACEBOOK_APP_SECRET"].present?
    provider :facebook,
             ENV.fetch("FACEBOOK_APP_ID").strip,
             ENV.fetch("FACEBOOK_APP_SECRET").strip,
             {
               scope: "email,public_profile",
               info_fields: "email,name"
             }
  end
end

if Rails.env.production? && ENV["RENDER_EXTERNAL_HOSTNAME"].present?
  OmniAuth.config.full_host = "https://#{ENV['RENDER_EXTERNAL_HOSTNAME'].strip}"
end

OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.on_failure = proc { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}
