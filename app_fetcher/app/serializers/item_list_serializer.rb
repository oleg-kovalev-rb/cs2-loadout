# typed: strict

class ItemListSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(catalog: ItemListQuery::ItemCatalog).returns(T::Hash[Symbol, T.untyped]) }
    def call(catalog)
      {
        meta: {
          page: catalog.pagination.page,
          per_page: catalog.pagination.per_page,
          total_count: catalog.total_count,
          total_pages: catalog.pagination.total_pages(catalog.total_count),
          gaining_count: catalog.price_change_stats.gaining_count,
          losing_count: catalog.price_change_stats.losing_count,
          last_synced_at: catalog.last_synced_at&.iso8601
        },
        items: catalog.items.map { |item| item_json(item, catalog.trends) }
      }
    end

    private

    sig do
      params(
        item: Item,
        trends: T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def item_json(item, trends)
      change = item.change_24h_cents || 0
      current = item.current_price_cents

      {
        market_hash_name: item.market_hash_name,
        metadata: ItemMetadataSerializer.call(item),
        current_price_cents: current,
        change_24h_cents: change,
        change_24h_percent: PriceChangePercent.call(current_cents: current, change_cents: change),
        trend_7d: (trends[item.market_hash_name] || []).map { |point| { at: point[:at], price_cents: point[:price_cents] } }
      }
    end
  end
end
