# frozen_string_literal: true

class UserMailer < ApplicationMailer
  default from: -> { ENV.fetch("SMTP_USERNAME", "no-reply@inventoryhub.io") }

  def confirmation_email(user, confirmation_url)
    @user = user
    @confirmation_url = confirmation_url
    mail(
      to: @user.email,
      subject: I18n.t("auth.confirm_email_subject", default: "Confirm your InventoryHub account")
    )
  end
end