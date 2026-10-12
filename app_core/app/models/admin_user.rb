# typed: strict

class AdminUser < ApplicationRecord
  extend T::Sig

  has_secure_password

  normalizes :email, with: ->(email) { email.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                     format: { with: URI::MailTo::EMAIL_REGEXP }
end
