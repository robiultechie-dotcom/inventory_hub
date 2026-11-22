# frozen_string_literal: true

require "securerandom"

class SessionsController < ApplicationController
  def create
    if params[:auth_mode] == "email_register"
      register_with_email_confirmation
      return
    end

    user = resolve_authenticated_user
    complete_sign_in_flow(user)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to root_path, alert: e.record.errors.full_messages.to_sentence
  end

  def omniauth
    auth = request.env["omniauth.auth"]
    if auth.blank?
      redirect_to root_path, alert: t("flashes.invalid_credentials")
      return
    end

    user = authenticate_from_omniauth(auth)
    complete_sign_in_flow(user)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to root_path, alert: e.record.errors.full_messages.to_sentence
  end

  def omniauth_failure
    redirect_to root_path, alert: params[:message].presence || t("flashes.invalid_credentials")
  end

  def confirm_email
    user = User.find_by_token_for(:email_confirmation, params[:token].to_s)

    if user && !user.blocked?
      user.confirm_email!
      user.update!(admin: true) if designated_admin_email?(user.email) && !user.admin?
      establish_secure_session!(user)
      redirect_to root_path, notice: t("flashes.email_confirmed", name: user.name)
    else
      redirect_to root_path, alert: t("flashes.invalid_token")
    end
  end

  def destroy
    reset_session_preserving_preferences!
    redirect_to root_path, notice: t("flashes.signed_out")
  end

  private

  def designated_admin_email?(email)
    designated = ENV["ADMIN_EMAIL"].to_s.strip.downcase
    designated.present? && email.to_s.strip.downcase == designated
  end

  def complete_sign_in_flow(user)
    if user&.blocked?
      redirect_to root_path, alert: t("flashes.account_blocked")
    elsif user&.email_unconfirmed?
      token = user.generate_token_for(:email_confirmation)
      deliver_confirmation_email!(user, confirm_email_url(token: token))
      redirect_to root_path, alert: t("flashes.email_unconfirmed", email: user.email)
    elsif user
      establish_secure_session!(user)
      redirect_back(fallback_location: root_path, notice: t("flashes.signed_in", name: user.name))
    else
      redirect_to root_path, alert: t("flashes.invalid_credentials")
    end
  rescue StandardError => e
    Rails.logger.error("[Auth Mailer Error] #{e.class}: #{e.message}")
    redirect_to root_path, alert: t("flashes.mail_delivery_failed")
  end

  def establish_secure_session!(user)
    reset_session_preserving_preferences!
    session[:user_id] = user.id
    cookies.permanent[:locale] = user.locale if %w[en es].include?(user.locale)
    cookies.permanent[:theme]  = user.theme  if %w[light dark].include?(user.theme)
  end

  def reset_session_preserving_preferences!
    saved_locale = session[:locale]
    saved_theme  = session[:theme]
    reset_session
    session[:locale] = saved_locale if saved_locale.present?
    session[:theme]  = saved_theme if saved_theme.present?
  end

  def resolve_authenticated_user
    if request.env["omniauth.auth"].present?
      authenticate_from_omniauth(request.env["omniauth.auth"])
    elsif params[:auth_mode] == "email_login"
      user = User.find_by(email: params[:email].to_s.strip.downcase)
      return nil unless user&.valid_password?(params[:password])

      user.update!(admin: true) if !user.email_unconfirmed? && designated_admin_email?(user.email) && !user.admin?
      user
    end
  end

  def register_with_email_confirmation
    email = params[:email].to_s.strip.downcase
    raw_password = params[:password].to_s

    if raw_password.length < 6
      redirect_to root_path, alert: t("flashes.password_too_short")
      return
    end

    existing_user = User.find_by(email: email)
    if existing_user
      if existing_user.email_unconfirmed?
        token = existing_user.generate_token_for(:email_confirmation)
        deliver_confirmation_email!(existing_user, confirm_email_url(token: token))
        redirect_to root_path, alert: t("flashes.email_unconfirmed", email: existing_user.email)
      else
        redirect_to root_path, alert: t("flashes.email_taken")
      end
      return
    end

    user = nil
    ActiveRecord::Base.transaction do
      user = User.new(
        name:     params[:name].to_s.strip.presence || email.split("@").first.capitalize,
        email:    email,
        provider: "email",
        uid:      "unconfirmed:#{SecureRandom.hex(12)}",
        admin:    designated_admin_email?(email)
      )
      user.password = raw_password
      user.save!

      token = user.generate_token_for(:email_confirmation)
      deliver_confirmation_email!(user, confirm_email_url(token: token))
    end

    redirect_to root_path, notice: t("flashes.confirmation_sent", email: user.email)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to root_path, alert: e.record.errors.full_messages.to_sentence
  rescue StandardError => e
    Rails.logger.error("[Registration Mailer Error] #{e.class}: #{e.message}")
    redirect_to root_path, alert: t("flashes.mail_delivery_failed")
  end

  def deliver_confirmation_email!(user, confirmation_url)
    UserMailer.confirmation_email(user, confirmation_url).deliver_now
    if Rails.env.development?
      Rails.logger.info("[DEV EMAIL] To: #{user.email} | Confirmation URL: #{confirmation_url}")
    end
  end

  def authenticate_from_omniauth(auth)
    provider = auth["provider"].to_s.downcase
    uid      = auth["uid"].to_s
    email    = auth.dig("info", "email").to_s.strip.downcase
    name     = auth.dig("info", "name").to_s.strip.presence || "User"

    is_designated_admin = designated_admin_email?(email)

    user = User.find_by(provider: provider, uid: uid) || (email.present? ? User.find_by(email: email) : nil)
    if user
      attrs = { provider: provider, uid: uid }
      attrs[:admin] = true if is_designated_admin && !user.admin?
      user.update!(attrs)
      user
    else
      new_user = User.new(
        name:     name,
        email:    email.presence || "#{uid}@#{provider}.oauth",
        provider: provider,
        uid:      uid,
        admin:    is_designated_admin
      )
      new_user.password = SecureRandom.hex(20)
      new_user.save!
      new_user
    end
  end
end
