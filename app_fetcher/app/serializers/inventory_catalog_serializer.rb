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
      change = summary.change_24h_cents
      base = summary.total_value_cents - change
      percent = base.zero? ? 0.0 : (change.to_f / base * 100).round(2)

      {
        steam_id: summary.steam_id,
        total_value_cents: summary.total_value_cents,
        change_24h_cents: change,
        change_24h_percent: percent,
        items_count: summary.items_count,
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
