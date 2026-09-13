# typed: strict

class Item < ApplicationRecord
  has_many :price_logs, dependent: :destroy

  store_accessor :metadata, :weapon_type, :item_name, :condition, :stattrak, :souvenir

  validates :market_hash_name, presence: true
  validates :market_hash_name, uniqueness: true

  def stattrak
    super.nil? ? false : super
  end
end
