# typed: strict

class InventoryCatalogSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(page: InventoryCatalogQuery::Page).returns(T::Hash[Symbol, T.untyped]) }
    def call(page)
      {
        meta: {
          page: page.pagination.page,
          per_page: page.pagination.per_page,
          total_count: page.total_count,
          total_pages: page.pagination.total_pages(page.total_count)
        },
        inventories: page.inventories.map { |summary| inventory_json(summary) }
      }
    end

    private

    sig { params(summary: InventoryCatalogQuery::InventorySummary).returns(T::Hash[Symbol, T.untyped]) }
    def inventory_json(summary)
      change = summary.change_available ? summary.change_24h_cents : 0
      base = summary.total_value_cents - change
      percent = summary.change_available && !base.zero? ? (change.to_f / base * 100).round(2) : 0.0

      {
        steam_id: summary.steam_id,
        total_value_cents: summary.total_value_cents,
        change_24h_cents: change,
        change_24h_percent: percent,
        items_count: summary.items_count,
        pricable_items_count: summary.pricable_items_count,
        priced_items_count: summary.priced_items_count,
        complete: summary.priced_items_count >= summary.pricable_items_count,
        change_basis_at: summary.change_basis_at,
        change_partial: summary.change_partial,
        change_available: summary.change_available,
        rarity_mix_percent: rarity_mix_percent(summary.rarity_counts),
        last_synced_at: summary.last_synced_at
      }
    end

    sig { params(rarity_counts: T::Hash[RarityTier, Integer]).returns(T::Hash[Symbol, Float]) }
    def rarity_mix_percent(rarity_counts)
      classified_total = rarity_counts.values.sum

      RarityTier.values.each_with_object({}) do |tier, mix|
        count = rarity_counts[tier] || 0
        mix[tier.serialize.to_sym] = classified_total.zero? ? 0.0 : (count.to_f / classified_total * 100).round(1)
      end
    end
  end
end
