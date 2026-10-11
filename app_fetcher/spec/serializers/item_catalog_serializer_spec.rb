require "rails_helper"

RSpec.describe ItemCatalogSerializer do
  describe ".call" do
    it "builds the meta hash from the page's pagination and counts" do
      item = Item.new(market_hash_name: "AK-47 | Redline (Field-Tested)", metadata: {})
      page = ItemCatalogQuery::Page.new(
        items: [ item ],
        pagination: Appliers::Pagination.new("2", "10"),
        total_count: 25,
        price_stats: ItemCatalogQuery::PriceStats.new(gaining_count: 3, losing_count: 1),
        trends: {},
        last_synced_at: "2024-01-02T00:00:00Z"
      )

      result = described_class.call(page)

      expect(result[:meta]).to eq(
        page: 2, per_page: 10, total_count: 25, total_pages: 3,
        gaining_count: 3, losing_count: 1, last_synced_at: "2024-01-02T00:00:00Z"
      )
    end

    it "exposes exactly the 7 contracted metadata keys and computes change_24h_percent" do
      item = Item.new(
        market_hash_name: "AK-47 | Redline (Field-Tested)",
        current_price_cents: 4218,
        change_24h_cents: 130,
        metadata: {
          marketable: true, tradable: true, souvenir: false, weapon_type: "AK-47", item_name: "Redline",
          category: "Rifles", condition: "Field-Tested", stattrak: false,
          icon_url: "https://example.com/icon.png", rarity: "Classified"
        }
      )
      page = ItemCatalogQuery::Page.new(
        items: [ item ], pagination: Appliers::Pagination.new(nil, nil), total_count: 1,
        price_stats: ItemCatalogQuery::PriceStats.new(gaining_count: 1, losing_count: 0),
        trends: {}, last_synced_at: nil
      )

      item_json = described_class.call(page)[:items].first

      expect(item_json[:metadata].keys).to contain_exactly(
        :weapon_type, :item_name, :category, :condition, :stattrak, :icon_url, :rarity
      )
      expect(item_json[:current_price_cents]).to eq(4218)
      expect(item_json[:change_24h_cents]).to eq(130)
      expect(item_json[:change_24h_percent]).to be_within(0.01).of(3.18)
    end

    it "reshapes trend_7d to at/price_cents only, dropping volume" do
      item = Item.new(market_hash_name: "AK-47 | Redline (Field-Tested)", metadata: {})
      page = ItemCatalogQuery::Page.new(
        items: [ item ], pagination: Appliers::Pagination.new(nil, nil), total_count: 1,
        price_stats: ItemCatalogQuery::PriceStats.new(gaining_count: 0, losing_count: 0),
        trends: { item.market_hash_name => [ { at: "2024-01-01T00:00:00Z", price_cents: 4000, volume: 12 } ] },
        last_synced_at: nil
      )

      trend_7d = described_class.call(page)[:items].first[:trend_7d]

      expect(trend_7d).to eq([ { at: "2024-01-01T00:00:00Z", price_cents: 4000 } ])
    end

    it "defaults change_24h_percent to 0.0 and current_price_cents to nil when there is no price" do
      item = Item.new(market_hash_name: "x", current_price_cents: nil, change_24h_cents: nil, metadata: {})
      page = ItemCatalogQuery::Page.new(
        items: [ item ], pagination: Appliers::Pagination.new(nil, nil), total_count: 1,
        price_stats: ItemCatalogQuery::PriceStats.new(gaining_count: 0, losing_count: 0),
        trends: {}, last_synced_at: nil
      )

      item_json = described_class.call(page)[:items].first

      expect(item_json[:change_24h_percent]).to eq(0.0)
      expect(item_json[:current_price_cents]).to be_nil
    end
  end
end
