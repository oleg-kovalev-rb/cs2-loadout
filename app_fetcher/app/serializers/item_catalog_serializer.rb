# typed: strict

class ItemCatalogSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(page: ItemCatalogQuery::Page).returns(T::Hash[Symbol, T.untyped]) }
    def call(page)
      {
        meta: {
          page: page.pagination.page,
          per_page: page.pagination.per_page,
          total_count: page.total_count,
          total_pages: page.pagination.total_pages(page.total_count),
          gaining_count: page.price_stats.gaining_count,
          losing_count: page.price_stats.losing_count,
          last_synced_at: page.last_synced_at
        },
        items: page.items.map { |item| item_json(item, page.trends) }
      }
    end

    private

    sig { params(item: Item, trends: T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]).returns(T::Hash[Symbol, T.untyped]) }
    def item_json(item, trends)
      change = item.change_24h_cents || 0
      current = item.current_price_cents
      base = current.nil? ? nil : current - change
      percent = (base.nil? || base.zero?) ? 0.0 : (change.to_f / base * 100).round(2)

      {
        market_hash_name: item.market_hash_name,
        metadata: {
          weapon_type: item.weapon_type,
          item_name: item.item_name,
          category: item.category,
          condition: item.condition,
          stattrak: item.stattrak,
          icon_url: item.icon_url,
          rarity: item.rarity
        },
        current_price_cents: current,
        change_24h_cents: change,
        change_24h_percent: percent,
        trend_7d: (trends[item.market_hash_name] || []).map { |point| { at: point[:at], price_cents: point[:price_cents] } }
      }
    end
  end
end
