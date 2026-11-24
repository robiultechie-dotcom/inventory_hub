# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email and enforces case-insensitive uniqueness" do
    user = User.create!(
      name: "Alice Tester",
      email: "  Alice.Tester@Example.COM ",
      provider: "email",
      uid: "confirmed:alice-1",
      password: "Password123!"
    )

    assert_equal "alice.tester@example.com", user.email

    duplicate = User.new(
      name: "Another Alice",
      email: "ALICE.TESTER@example.com",
      provider: "email",
      uid: "confirmed:alice-2",
      password: "Password123!"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:email].any?
  end

  test "hashes password securely and validates credentials" do
    user = User.create!(
      name: "Bob Tester",
      email: "bob.tester@example.com",
      provider: "email",
      uid: "confirmed:bob-1",
      password: "StrongPassword!23"
    )

    assert user.encrypted_password.present?
    assert_not_equal "StrongPassword!23", user.encrypted_password
    assert user.valid_password?("StrongPassword!23")
    assert_not user.valid_password?("WrongPassword")
  end

  test "confirms email via signed token and invalidates token after confirmation" do
    user = User.create!(
      name: "Clara Tester",
      email: "clara.tester@example.com",
      provider: "email",
      uid: "unconfirmed:clara-token-1",
      password: "Password123!"
    )

    assert user.email_unconfirmed?

    token = user.generate_token_for(:email_confirmation)
    assert_equal user, User.find_by_token_for(:email_confirmation, token)

    user.confirm_email!
    assert_not user.reload.email_unconfirmed?
    assert_nil User.find_by_token_for(:email_confirmation, token)
  end
end
