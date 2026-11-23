# frozen_string_literal: true

require Rails.root.join("lib/google_apps_script_delivery")

ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :google_apps_script, GoogleAppsScriptDelivery

  if Rails.env.production? && ENV["GOOGLE_MAILER_URL"].present?
    self.delivery_method = :google_apps_script
    self.google_apps_script_settings = {
      webhook_url: ENV["GOOGLE_MAILER_URL"],
      secret: ENV["GOOGLE_MAILER_SECRET"]
    }
  end
end

Rails.application.config.after_initialize do
  if Rails.env.production? && ENV["GOOGLE_MAILER_URL"].present?
    settings = {
      webhook_url: ENV["GOOGLE_MAILER_URL"],
      secret: ENV["GOOGLE_MAILER_SECRET"]
    }

    Rails.application.config.action_mailer.delivery_method = :google_apps_script
    Rails.application.config.action_mailer.google_apps_script_settings = settings
    ActionMailer::Base.delivery_method = :google_apps_script
    ActionMailer::Base.google_apps_script_settings = settings

    if defined?(UserMailer)
      UserMailer.delivery_method = :google_apps_script
      UserMailer.google_apps_script_settings = settings
    end

    Rails.logger.info("[Mailer Config] Active delivery_method: #{ActionMailer::Base.delivery_method}")
  end
end
