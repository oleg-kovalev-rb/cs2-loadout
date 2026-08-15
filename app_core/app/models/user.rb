# typed: strict

class User < ApplicationRecord
  extend T::Sig

  validates :steam_id, presence: true, uniqueness: true
end
