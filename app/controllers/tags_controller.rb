# frozen_string_literal: true

class TagsController < ApplicationController
  # Section 5: Dropdown shows existing tags from the database that start with the entered text
  def autocomplete
    q = params[:q].to_s.strip.downcase
    scope = Tag.order(inventories_count: :desc, name: :asc).limit(15)
    scope = scope.where("LOWER(name) LIKE ?", "#{Tag.sanitize_sql_like(q)}%") if q.present?

    render json: scope.pluck(:name)
  end
end