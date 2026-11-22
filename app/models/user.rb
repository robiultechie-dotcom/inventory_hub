# frozen_string_literal: true

require "bcrypt"

class User < ApplicationRecord
  has_many :owned_inventories, class_name: "Inventory", foreign_key: :creator_id, inverse_of: :creator, dependent: :destroy
  has_many :created_items, class_name: "Item", foreign_key: :created_by_id, inverse_of: :created_by, dependent: :destroy
  has_many :inventory_accesses, dependent: :destroy
  has_many :accessible_inventories, through: :inventory_accesses, source: :inventory
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :email,
            presence: true,
            length: { maximum: 160 },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }

  before_validation :normalize_email

  # Rails 8 cryptographic signed token (expires in 24h & auto-invalidates once uid changes)
  generates_token_for :email_confirmation, expires_in: 24.hours do
    uid
  end

  def password=(raw_password)
    return if raw_password.blank?

    self.encrypted_password = BCrypt::Password.create(raw_password)
  end

  def valid_password?(raw_password)
    return false if encrypted_password.blank? || raw_password.blank?

    BCrypt::Password.new(encrypted_password) == raw_password.to_s
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def email_unconfirmed?
    provider == "email" && uid.to_s.start_with?("unconfirmed:")
  end

  def confirm_email!
    update!(uid: "confirmed:#{id}")
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
