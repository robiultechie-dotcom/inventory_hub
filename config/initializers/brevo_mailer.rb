# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method(
    :brevo_api,
    BrevoApiDelivery,
    api_key: ENV["BREVO_API_KEY"].to_s.strip
  )

  if !Rails.env.test? && ENV["BREVO_API_KEY"].present?
    ActionMailer::Base.delivery_method = :brevo_api
  end
end
