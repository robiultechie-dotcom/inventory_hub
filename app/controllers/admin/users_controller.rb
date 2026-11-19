# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    before_action :require_admin!

    def index
      @users = User.order(created_at: :desc).to_a
      @owned_counts = Inventory.where(creator_id: @users.map(&:id)).group(:creator_id).count
    end

    def bulk_action
      ids = Array(params[:ids]).map(&:to_i).uniq
      operation = (params[:operation].presence || params[:action_type]).to_s
      target_users = User.where(id: ids)

      if target_users.empty?
        redirect_to admin_users_path, alert: t("flashes.no_users_selected")
        return
      end

      self_affected = ids.include?(current_user.id)
      now = Time.current

      User.transaction do
        case operation
        when "block"
          target_users.update_all(blocked: true, updated_at: now)
          if self_affected
            reset_session
            redirect_to root_path, alert: t("flashes.account_blocked")
            return
          end
        when "unblock"
          target_users.update_all(blocked: false, updated_at: now)
        when "make_admin"
          target_users.update_all(admin: true, updated_at: now)
        when "remove_admin"
          target_users.update_all(admin: false, updated_at: now)
          if self_affected
            redirect_to root_path, notice: t("flashes.self_demoted")
            return
          end
        when "delete"
          target_users.destroy_all
          if self_affected
            reset_session
            redirect_to root_path, notice: t("flashes.signed_out")
            return
          end
        end
      end

      redirect_to admin_users_path, notice: t("flashes.users_updated")
    end

    private

    def require_admin!
      if current_user.nil?
        redirect_to root_path, alert: t("flashes.auth_required")
      elsif !current_user.admin?
        redirect_to root_path, alert: t("flashes.admin_required")
      end
    end
  end
end