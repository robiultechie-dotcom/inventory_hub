# frozen_string_literal: true

require Rails.root.join("lib/google_apps_script_delivery")

ActiveSupport.on_load(:action_mailer) do
  add_delivery_method(
    :google_apps_script,
    GoogleAppsScriptDelivery,
    webhook_url: ENV["GOOGLE_MAILER_URL"],
    secret: ENV["GOOGLE_MAILER_SECRET"]
  )

  if Rails.env.production? && ENV["GOOGLE_MAILER_URL"].present?
    self.delivery_method = :google_apps_script
    Rails.logger&.info("[Mailer Config] Active delivery_method: #{delivery_method}")
  end
end
