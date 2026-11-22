# frozen_string_literal: true

class PreferencesController < ApplicationController
  def update_theme
    theme = %w[light dark].include?(params[:theme]) ? params[:theme] : "light"
    cookies.permanent[:theme] = theme
    current_user&.update(theme: theme)

    redirect_back(fallback_location: root_path)
  end

  def update_locale
    locale = %w[en es].include?(params[:locale]) ? params[:locale] : "en"
    cookies.permanent[:locale] = locale
    current_user&.update(locale: locale)

    redirect_back(fallback_location: root_path)
  end
end
