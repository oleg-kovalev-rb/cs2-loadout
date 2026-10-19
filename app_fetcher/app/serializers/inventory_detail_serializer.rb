# typed: strict

class InventoryDetailSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(page: InventoryDetailQuery::Page).returns(T::Hash[Symbol, T.untyped]) }
    def call(page)
      {
        steam_id: page.steam_id,
        last_synced_at: page.last_synced_at,
        portfolio: portfolio_json(page),
        items_count: page.items_count,
        avg_item_value_cents: page.avg_item_value_cents,
        priciest_item: priciest_item_json(page.priciest_item),
        rarity_breakdown: rarity_breakdown_json(page.rarity_counts),
        top_items: top_items_json(page)
      }
    end

    private

    sig { params(page: InventoryDetailQuery::Page).returns(T::Hash[Symbol, T.untyped]) }
    def portfolio_json(page)
      {
        total_value_cents: page.total_value_cents,
        change_cents: page.change_cents,
        change_percent: page.change_percent,
        change_basis_at: page.change_basis_at,
        change_partial: page.change_partial,
        change_available: page.change_available,
        complete: page.complete,
        priced_items_count: page.priced_items_count,
        pricable_items_count: page.pricable_items_count,
        oldest_price_at: page.oldest_price_at&.iso8601,
        period: page.period.serialize,
        history: page.history.map do |point|
          {
            at: point.at,
            total_value_cents: point.total_value_cents,
            complete: point.complete,
            priced_items_count: point.priced_items_count,
            pricable_items_count: point.pricable_items_count
          }
        end
      }
    end

    sig { params(item: T.nilable(Item)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def priciest_item_json(item)
      return nil if item.nil?

      {
        market_hash_name: item.market_hash_name,
        metadata: metadata_json(item),
        current_price_cents: item.current_price_cents,
        price_updated_at: item.price_updated_at&.iso8601
      }
    end

    sig { params(rarity_counts: T::Hash[RarityTier, Integer]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def rarity_breakdown_json(rarity_counts)
      classified_total = rarity_counts.values.sum

      RarityTier.values.map do |tier|
        count = rarity_counts[tier] || 0
        percent = classified_total.zero? ? 0.0 : (count.to_f / classified_total * 100).round(1)

        { tier: tier.serialize, count: count, percent: percent }
      end
    end

    sig { params(page: InventoryDetailQuery::Page).returns(T::Hash[Symbol, T.untyped]) }
    def top_items_json(page)
      {
        meta: {
          page: page.top_items_pagination.page,
          per_page: page.top_items_pagination.per_page,
          total_count: page.top_items_total_count,
          total_pages: page.top_items_pagination.total_pages(page.top_items_total_count)
        },
        entries: page.top_items.map { |item| item_entry_json(item, page.trends) }
      }
    end

    sig { params(item: Item, trends: T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]).returns(T::Hash[Symbol, T.untyped]) }
    def item_entry_json(item, trends)
      change = item.change_24h_cents || 0
      current = item.current_price_cents
      base = current.nil? ? nil : current - change
      percent = (base.nil? || base.zero?) ? 0.0 : (change.to_f / base * 100).round(2)

      {
        market_hash_name: item.market_hash_name,
        metadata: metadata_json(item),
        current_price_cents: current,
        change_24h_cents: change,
        change_24h_percent: percent,
        price_updated_at: item.price_updated_at&.iso8601,
        trend_7d: (trends[item.market_hash_name] || []).map { |point| { at: point[:at], price_cents: point[:price_cents] } }
      }
    end

    sig { params(item: Item).returns(T::Hash[Symbol, T.untyped]) }
    def metadata_json(item)
      {
        weapon_type: item.weapon_type,
        item_name: item.item_name,
        category: item.category,
        condition: item.condition,
        stattrak: item.stattrak,
        icon_url: item.icon_url,
        rarity: item.rarity
      }
    end
  end
end
