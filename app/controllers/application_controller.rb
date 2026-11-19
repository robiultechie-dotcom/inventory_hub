# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :set_locale
  helper_method :current_user, :current_theme, :all_categories, :available_oauth_users

  private

  def set_locale
    requested = params[:locale] || cookies[:locale] || session[:locale]
    I18n.locale = %w[en es].include?(requested.to_s) ? requested.to_sym : I18n.default_locale
  end

  def current_theme
    theme = cookies[:theme] || session[:theme]
    %w[light dark].include?(theme.to_s) ? theme.to_s : "light"
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id]) if session[:user_id].present?
    if @current_user&.blocked?
      session.delete(:user_id)
      @current_user = nil
    end
    @current_user
  end

  def all_categories
    @all_categories ||= Category.order(:name).to_a
  end

  def available_oauth_users
    @available_oauth_users ||= User.where(blocked: false).order(:id).limit(4).to_a
  end

  def authenticate_user!
    return if current_user.present?

    respond_to do |format|
      format.json { render json: { error: t("flashes.auth_required", default: "Please sign in.") }, status: :unauthorized }
      format.html { redirect_to root_path, alert: t("flashes.auth_required", default: "Please sign in.") }
    end
  end

  def require_admin!
    if current_user.nil?
      redirect_to root_path, alert: t("flashes.auth_required", default: "Please sign in.")
    elsif !current_user.admin?
      redirect_to root_path, alert: t("flashes.admin_required", default: "Admin access required.")
    end
  end
  alias authenticate_admin! require_admin!
end