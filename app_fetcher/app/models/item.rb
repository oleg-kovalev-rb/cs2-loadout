# typed: strict

class Item < ApplicationRecord
  extend T::Sig

  PRICE_STALE_AFTER = T.let(1.hour, ActiveSupport::Duration)

  has_many :price_logs, dependent: :destroy

  store_accessor :metadata, :weapon_type, :item_name, :condition, :stattrak, :souvenir, :icon_url,
                 :marketable, :tradable, :rarity, :category

  validates :market_hash_name, presence: true
  validates :market_hash_name, uniqueness: true

  scope :marketable, -> { where("metadata @> ?", { marketable: true }.to_json) }
  scope :stale_or_unpriced, -> { where("updated_at < ? OR current_price_cents IS NULL", PRICE_STALE_AFTER.ago) }
  scope :due_for_price_update, -> { marketable.stale_or_unpriced }

  scope :by_categories, ->(categories) { where("metadata->>'category' IN (?)", categories) if categories.present? }
  scope :by_rarities, ->(rarities) { where("metadata->>'rarity' IN (?)", rarities) if rarities.present? }
  scope :stattrak_only, -> { where("metadata @> ?", { stattrak: true }.to_json) }
  scope :matching_search, lambda { |term|
    where("metadata->>'item_name' ILIKE ?", "%#{sanitize_sql_like(term)}%") if term.present?
  }
  scope :sorted_by, lambda { |sort|
    case sort
    when "price_desc" then order(current_price_cents: :desc)
    when "price_asc" then order(current_price_cents: :asc)
    when "name_asc" then order(Arel.sql("metadata->>'item_name' ASC"))
    else order(change_24h_cents: :desc)
    end
  }

  sig { returns(T::Boolean) }
  def stattrak
    !!metadata["stattrak"]
  end
end
