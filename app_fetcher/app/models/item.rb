# typed: strict

class Item < ApplicationRecord
  extend T::Sig

  PRICE_STALE_AFTER = T.let(1.hour, ActiveSupport::Duration)

  has_many :price_logs, dependent: :destroy

  store_accessor :metadata, :weapon_type, :item_name, :condition, :stattrak, :souvenir, :icon_url,
                 :marketable, :tradable, :rarity

  validates :market_hash_name, presence: true
  validates :market_hash_name, uniqueness: true

  scope :marketable, -> { where("metadata @> ?", { marketable: true }.to_json) }
  scope :stale_or_unpriced, -> { where("updated_at < ? OR current_price_cents IS NULL", PRICE_STALE_AFTER.ago) }
  scope :due_for_price_update, -> { marketable.stale_or_unpriced }

  sig { returns(T::Boolean) }
  def stattrak
    super.nil? ? false : super
  end
end
