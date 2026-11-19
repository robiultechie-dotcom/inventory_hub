# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :inventory
  belongs_to :user

  validates :body, presence: true
end