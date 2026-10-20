# typed: strict

class InventoryListSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(result: InventoryListQuery::InventorySummaries).returns(T::Hash[Symbol, T.untyped]) }
    def call(result)
      {
        meta: {
          page: result.pagination.page,
          per_page: result.pagination.per_page,
          total_count: result.total_count,
          total_pages: result.pagination.total_pages(result.total_count)
        },
        inventories: result.inventories.map { |summary| inventory_json(summary) }
      }
    end

    sig { params(summary: InventoryListQuery::InventorySummary).returns(T::Hash[Symbol, T.untyped]) }
    def inventory_json(summary)
      snapshot = summary.snapshot
      delta = summary.delta

      {
        steam_id: summary.steam_id,
        total_value_cents: snapshot.total_value_cents,
        change_24h_cents: delta.cents,
        change_24h_percent: delta.percent,
        items_count: snapshot.items_count,
        pricable_items_count: snapshot.pricable_items_count,
        priced_items_count: snapshot.priced_items_count,
        complete: snapshot.complete?,
        change_basis_at: delta.basis_at&.to_date&.iso8601,
        change_partial: delta.partial,
        change_available: delta.available,
        rarity_breakdown: RarityBreakdownSerializer.call(summary.rarity_counts),
        last_synced_at: summary.last_synced_at.iso8601
      }
    end
  end
end
