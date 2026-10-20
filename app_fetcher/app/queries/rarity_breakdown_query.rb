# typed: strict

class RarityBreakdownQuery
  extend T::Sig

  class << self
    extend T::Sig

    sig do
      params(user_inventory_ids: T::Array[Integer])
        .returns(T::Hash[Integer, T::Hash[RarityTier, Integer]])
    end
    def call(user_inventory_ids)
      counts = T.let({}, T::Hash[Integer, T::Hash[RarityTier, Integer]])
      return counts if user_inventory_ids.empty?

      UserInventoryItem
        .joins(:item)
        .where(user_inventory_id: user_inventory_ids)
        .pluck(:user_inventory_id, "items.market_hash_name", Arel.sql("items.metadata ->> 'rarity'"))
        .each do |user_inventory_id, market_hash_name, rarity|
          tier = RarityTier.for(market_hash_name:, rarity:)
          next unless tier

          inventory_counts = (counts[user_inventory_id] ||= {})
          inventory_counts[tier] = (inventory_counts[tier] || 0) + 1
        end

      counts
    end
  end
end
