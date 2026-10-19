require "rails_helper"

RSpec.describe InventoryDetailSerializer do
  describe ".call" do
    it "exposes exactly the contracted top-level keys" do
      result = described_class.call(build_page)

      expect(result.keys).to contain_exactly(
        :steam_id, :last_synced_at, :portfolio, :items_count, :avg_item_value_cents,
        :priciest_item, :rarity_breakdown, :top_items
      )
    end

    it "builds the portfolio hash, serializing period and reshaping history" do
      page = build_page(
        period: PricePeriod::ThirtyDays,
        total_value_cents: 5000, change_cents: 500, change_percent: 11.11,
        change_basis_at: "2024-01-01T00:00:00Z", change_partial: false, change_available: true,
        complete: true, priced_items_count: 2, pricable_items_count: 2,
        oldest_price_at: Time.utc(2024, 1, 2, 12, 0, 0),
        history: [
          InventoryDetailQuery::HistoryPoint.new(
            at: "2024-01-01T00:00:00Z", total_value_cents: 4500, complete: true,
            priced_items_count: 2, pricable_items_count: 2
          )
        ]
      )

      portfolio = described_class.call(page)[:portfolio]

      expect(portfolio).to eq(
        total_value_cents: 5000, change_cents: 500, change_percent: 11.11,
        change_basis_at: "2024-01-01T00:00:00Z", change_partial: false, change_available: true,
        complete: true, priced_items_count: 2, pricable_items_count: 2,
        oldest_price_at: "2024-01-02T12:00:00Z", period: "30d",
        history: [
          {
            at: "2024-01-01T00:00:00Z", total_value_cents: 4500, complete: true,
            priced_items_count: 2, pricable_items_count: 2
          }
        ]
      )
    end

    it "returns nil priciest_item when there is none" do
      result = described_class.call(build_page(priciest_item: nil))

      expect(result[:priciest_item]).to be_nil
    end

    it "builds priciest_item with exactly the 7 metadata keys and no change/trend fields" do
      item = Item.new(
        market_hash_name: "★ Karambit | Doppler (Factory New)",
        current_price_cents: 214_000,
        price_updated_at: Time.utc(2024, 1, 1, 12, 0, 0),
        metadata: { weapon_type: "Karambit", item_name: "Doppler", category: "Knives", condition: "Factory New", stattrak: false, icon_url: "https://x", rarity: "Covert" }
      )

      priciest_item = described_class.call(build_page(priciest_item: item))[:priciest_item]

      aggregate_failures do
        expect(priciest_item.keys).to contain_exactly(
          :market_hash_name, :metadata, :current_price_cents, :price_updated_at
        )
        expect(priciest_item[:metadata].keys).to contain_exactly(
          :weapon_type, :item_name, :category, :condition, :stattrak, :icon_url, :rarity
        )
        expect(priciest_item[:current_price_cents]).to eq(214_000)
        expect(priciest_item[:price_updated_at]).to eq("2024-01-01T12:00:00Z")
      end
    end

    it "builds rarity_breakdown with all 7 tiers, percent against the classified count" do
      rarity_breakdown = described_class.call(
        build_page(rarity_counts: { RarityTier::Covert => 1, RarityTier::Classified => 3 })
      )[:rarity_breakdown]

      covert = rarity_breakdown.find { |entry| entry[:tier] == "covert" }
      classified = rarity_breakdown.find { |entry| entry[:tier] == "classified" }
      gold = rarity_breakdown.find { |entry| entry[:tier] == "gold" }

      aggregate_failures do
        expect(rarity_breakdown.size).to eq(7)
        expect(covert).to eq(tier: "covert", count: 1, percent: 25.0)
        expect(classified).to eq(tier: "classified", count: 3, percent: 75.0)
        expect(gold).to eq(tier: "gold", count: 0, percent: 0.0)
      end
    end

    it "builds top_items meta from pagination/total_count" do
      page = build_page(top_items_pagination: Appliers::Pagination.new("2", "12"), top_items_total_count: 25)

      meta = described_class.call(page)[:top_items][:meta]

      expect(meta).to eq(page: 2, per_page: 12, total_count: 25, total_pages: 3)
    end

    it "builds top_items entries with the full item shape, change_24h_percent, and reshaped trend_7d" do
      item = Item.new(
        market_hash_name: "AK-47 | Redline (Field-Tested)",
        current_price_cents: 4218, change_24h_cents: 130,
        price_updated_at: Time.utc(2024, 1, 1, 12, 0, 0),
        metadata: { weapon_type: "AK-47", item_name: "Redline", category: "Rifles", condition: "Field-Tested", stattrak: false, icon_url: "https://x", rarity: "Classified" }
      )
      page = build_page(
        top_items: [ item ],
        trends: { item.market_hash_name => [ { at: "2024-01-01T00:00:00Z", price_cents: 4000, volume: 12 } ] }
      )

      entry = described_class.call(page)[:top_items][:entries].first

      aggregate_failures do
        expect(entry[:metadata].keys).to contain_exactly(
          :weapon_type, :item_name, :category, :condition, :stattrak, :icon_url, :rarity
        )
        expect(entry[:current_price_cents]).to eq(4218)
        expect(entry[:change_24h_cents]).to eq(130)
        expect(entry[:change_24h_percent]).to be_within(0.01).of(3.18)
        expect(entry[:price_updated_at]).to eq("2024-01-01T12:00:00Z")
        expect(entry[:trend_7d]).to eq([ { at: "2024-01-01T00:00:00Z", price_cents: 4000 } ])
      end
    end
  end

  def build_page(steam_id: "76561198000000001", last_synced_at: "2024-01-01T00:00:00Z",
                 period: PricePeriod::SevenDays, total_value_cents: 0, change_cents: 0, change_percent: 0.0,
                 change_basis_at: nil, change_partial: false, change_available: false,
                 history: [], items_count: 0, pricable_items_count: 0, priced_items_count: 0,
                 complete: true, oldest_price_at: nil, avg_item_value_cents: 0, priciest_item: nil,
                 rarity_counts: {}, top_items: [], top_items_pagination: Appliers::Pagination.new(nil, nil),
                 top_items_total_count: 0, trends: {})
    InventoryDetailQuery::Page.new(
      steam_id: steam_id, last_synced_at: last_synced_at, period: period,
      total_value_cents: total_value_cents, change_cents: change_cents, change_percent: change_percent,
      change_basis_at: change_basis_at, change_partial: change_partial,
      change_available: change_available, history: history, items_count: items_count,
      pricable_items_count: pricable_items_count, priced_items_count: priced_items_count,
      complete: complete, oldest_price_at: oldest_price_at, avg_item_value_cents: avg_item_value_cents,
      priciest_item: priciest_item, rarity_counts: rarity_counts, top_items: top_items,
      top_items_pagination: top_items_pagination, top_items_total_count: top_items_total_count, trends: trends
    )
  end
end
