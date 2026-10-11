# typed: strict

class Item < ApplicationRecord
  extend T::Sig

  has_many :price_logs, dependent: :destroy

  store_accessor :metadata, :weapon_type, :item_name, :condition, :stattrak, :souvenir, :icon_url,
                 :marketable, :tradable, :rarity

  validates :market_hash_name, presence: true
  validates :market_hash_name, uniqueness: true

  sig { returns(T::Boolean) }
  def stattrak
    super.nil? ? false : super
  end
end
