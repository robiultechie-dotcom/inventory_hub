# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :authenticate_user!, only: %i[create]
  before_action :set_inventory

  def index
    @comments = @inventory.comments.includes(:user)
    latest_marker = [@comments.size, @comments.maximum(:updated_at), I18n.locale]

    if stale?(etag: latest_marker, public: false)
      render partial: "comments/list", locals: { comments: @comments }, layout: false
    end
  end

  def create
    @comment = @inventory.comments.build(comment_params.merge(user: current_user))
    if @comment.save
      if request.xhr? || request.format.json?
        @comments = @inventory.comments.includes(:user)
        render partial: "comments/list", locals: { comments: @comments }, layout: false, status: :created
      else
        redirect_to inventory_path(@inventory, tab: "discussion")
      end
    else
      redirect_to inventory_path(@inventory, tab: "discussion"), alert: @comment.errors.full_messages.to_sentence
    end
  end

  private

  def set_inventory
    @inventory = Inventory.find(params[:inventory_id])
  end

  def comment_params
    params.require(:comment).permit(:body)
  end
end