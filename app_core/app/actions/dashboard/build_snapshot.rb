# typed: strict

module Dashboard
  class BuildSnapshot
    extend T::Sig

    sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
    def self.call(user)
      inventory = Steam::InventoryFetcher.call(user.steam_id)
      items = inventory ? inventory[:items] : []

      enriched_items = items.map { |item| Dashboard::ItemEnricher.call(item) }

      {
        items_count: enriched_items.size,
        items: enriched_items,
        portfolio: Dashboard::Stub::PortfolioSeries.call(enriched_items),
        market_volume: Dashboard::Stub::MarketVolume.call
      }
    end
  end
end
