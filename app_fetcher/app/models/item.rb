# typed: strict

class Item < ApplicationRecord
  store_accessor :condition, :item_name, :metadata, :weapon_type, :souvenir, :stattrak

  validates :market_hash_name, presence: true
  validates :market_hash_name, uniqueness: true

  def stattrak
    super.nil? ? false : super
  end
end
