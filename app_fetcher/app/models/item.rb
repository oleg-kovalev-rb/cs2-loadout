# typed: strict

class Item < ApplicationRecord
  store_accessor :metadata, :weapon_type, :item_name, :condition, :stattrak

  validates :market_hash_name, :appid, :item_type, presence: true
  validates :market_hash_name, uniqueness: true

  def stattrak
    super.nil? ? false : super
  end
end
