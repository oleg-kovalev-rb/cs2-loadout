# typed: strict

module Dashboard
  class ItemEnricher
    extend T::Sig

    sig { params(item: Steam::InventoryFetcher::InventoryItem).returns(T::Hash[Symbol, T.untyped]) }
    def self.call(item)
      price_cents = item[:current_price_cents] || 0

      {
        market_hash_name: item[:market_hash_name],
        weapon_type: item[:metadata][:weapon_type],
        item_name: item[:metadata][:item_name],
        condition: item[:metadata][:condition],
        stattrak: item[:metadata][:stattrak] || false,
        current_price_cents: price_cents,
        change_24h_cents: Dashboard::Stub::PriceChange.call(item[:market_hash_name], price_cents)
      }
    end
  end
end
