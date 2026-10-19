# typed: strict

class InventoryDetailSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(result: InventoryDetailQuery::InventoryDetails).returns(T::Hash[Symbol, T.untyped]) }
    def call(result)
      snapshot = T.must(result.value.snapshot)

      {
        steam_id: result.steam_id,
        last_synced_at: result.last_synced_at.iso8601,
        portfolio: portfolio_json(result),
        items_count: snapshot.items_count,
        avg_item_value_cents: result.avg_item_value_cents,
        priciest_item: priciest_item_json(result.priciest_item),
        rarity_breakdown: RarityBreakdownSerializer.call(result.rarity_counts),
        top_items: top_items_json(result)
      }
    end

    private

    sig { params(result: InventoryDetailQuery::InventoryDetails).returns(T::Hash[Symbol, T.untyped]) }
    def portfolio_json(result)
      snapshot = T.must(result.value.snapshot)
      delta = result.value.history.delta

      {
        total_value_cents: snapshot.total_value_cents,
        change_cents: delta.cents,
        change_percent: delta.percent,
        change_basis_at: delta.basis_at&.iso8601,
        change_partial: delta.partial,
        change_available: delta.available,
        complete: snapshot.complete?,
        priced_items_count: snapshot.priced_items_count,
        pricable_items_count: snapshot.pricable_items_count,
        oldest_price_at: snapshot.oldest_price_at&.iso8601,
        period: result.range.serialize,
        history: result.value.history.points.map do |point|
          {
            at: point.at.iso8601,
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
        metadata: ItemMetadataSerializer.call(item),
        current_price_cents: item.current_price_cents,
        price_updated_at: item.price_updated_at&.iso8601
      }
    end

    sig { params(result: InventoryDetailQuery::InventoryDetails).returns(T::Hash[Symbol, T.untyped]) }
    def top_items_json(result)
      items = result.items

      {
        meta: {
          page: items.pagination.page,
          per_page: items.pagination.per_page,
          total_count: items.total_count,
          total_pages: items.pagination.total_pages(items.total_count)
        },
        entries: items.entries.map { |item| item_entry_json(item, items.trends) }
      }
    end

    sig do
      params(
        item: Item,
        trends: T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def item_entry_json(item, trends)
      change = item.change_24h_cents || 0
      current = item.current_price_cents

      {
        market_hash_name: item.market_hash_name,
        metadata: ItemMetadataSerializer.call(item),
        current_price_cents: current,
        change_24h_cents: change,
        change_24h_percent: PriceChangePercent.call(current_cents: current, change_cents: change),
        price_updated_at: item.price_updated_at&.iso8601,
        trend_7d: (trends[item.market_hash_name] || []).map { |point| { at: point[:at], price_cents: point[:price_cents] } }
      }
    end
  end
end
