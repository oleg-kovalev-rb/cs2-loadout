require "rails_helper"

RSpec.describe InventoryDetailSerializer do
  describe ".call" do
    it "exposes exactly the contracted top-level keys" do
      result = described_class.call(build_details)

      expect(result.keys).to contain_exactly(
        :steam_id, :last_synced_at, :portfolio, :items_count, :avg_item_value_cents,
        :priciest_item, :rarity_breakdown, :top_items
      )
    end

    it "builds the portfolio hash, serializing period and reshaping history" do
      details = build_details(
        range: Options::DateRange::Last30Days,
        total_value_cents: 5000, change_cents: 500, change_percent: 11.11,
        change_basis_at: Time.utc(2024, 1, 1), change_partial: false, change_available: true,
        complete: true, priced_items_count: 2, pricable_items_count: 2,
        oldest_price_at: Time.utc(2024, 1, 2, 12, 0, 0),
        history: [
          InventoryValueQuery::ValueHistory::Point.new(
            at: Time.utc(2024, 1, 1), total_value_cents: 4500, complete: true,
            priced_items_count: 2, pricable_items_count: 2
          )
        ]
      )

      portfolio = described_class.call(details)[:portfolio]

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
      result = described_class.call(build_details(priciest_item: nil))

      expect(result[:priciest_item]).to be_nil
    end

    it "builds priciest_item with exactly the 7 metadata keys and no change/trend fields" do
      item = Item.new(
        market_hash_name: "★ Karambit | Doppler (Factory New)",
        current_price_cents: 214_000,
        price_updated_at: Time.utc(2024, 1, 1, 12, 0, 0),
        metadata: { weapon_type: "Karambit", item_name: "Doppler", category: "Knives", condition: "Factory New", stattrak: false, icon_url: "https://x", rarity: "Covert" }
      )

      priciest_item = described_class.call(build_details(priciest_item: item))[:priciest_item]

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
        build_details(rarity_counts: { RarityTier::Covert => 1, RarityTier::Classified => 3 })
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
      details = build_details(items_pagination: Appliers::Pagination.new("2", "12"), items_total_count: 25)

      meta = described_class.call(details)[:top_items][:meta]

      expect(meta).to eq(page: 2, per_page: 12, total_count: 25, total_pages: 3)
    end

    it "builds top_items entries with the full item shape, change_24h_percent, and reshaped trend_7d" do
      item = Item.new(
        market_hash_name: "AK-47 | Redline (Field-Tested)",
        current_price_cents: 4218, change_24h_cents: 130,
        price_updated_at: Time.utc(2024, 1, 1, 12, 0, 0),
        metadata: { weapon_type: "AK-47", item_name: "Redline", category: "Rifles", condition: "Field-Tested", stattrak: false, icon_url: "https://x", rarity: "Classified" }
      )
      details = build_details(
        entries: [ item ],
        trends: { item.market_hash_name => [ { at: "2024-01-01T00:00:00Z", price_cents: 4000, volume: 12 } ] }
      )

      entry = described_class.call(details)[:top_items][:entries].first

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

  def build_details(steam_id: "76561198000000001", last_synced_at: Time.utc(2024, 1, 1),
                    range: Options::DateRange::Last7Days, total_value_cents: 0, change_cents: 0,
                    change_percent: 0.0, change_basis_at: nil, change_partial: false,
                    change_available: false, history: [], items_count: 0, pricable_items_count: 0,
                    priced_items_count: 0, complete: true, oldest_price_at: nil,
                    avg_item_value_cents: 0, priciest_item: nil, rarity_counts: {},
                    entries: [], items_pagination: Appliers::Pagination.new(nil, nil),
                    items_total_count: 0, trends: {})
    snapshot = InventoryValueQuery::ValueSnapshot.new(
      total_value_cents: total_value_cents,
      items_count: items_count,
      pricable_items_count: pricable_items_count,
      priced_items_count: priced_items_count,
      oldest_price_at: oldest_price_at
    )
    delta = InventoryValueQuery::ValueDelta.new(
      cents: change_cents,
      percent: change_percent,
      basis_at: change_basis_at,
      partial: change_partial,
      available: change_available
    )
    value = InventoryValueQuery::InventoryValue.new(
      snapshot: snapshot,
      history: InventoryValueQuery::ValueHistory.new(points: history, delta: delta)
    )
    items = InventoryDetailQuery::InventoryItems.new(
      entries: entries,
      pagination: items_pagination,
      total_count: items_total_count,
      trends: trends
    )
    InventoryDetailQuery::InventoryDetails.new(
      steam_id: steam_id,
      last_synced_at: last_synced_at,
      range: range,
      value: value,
      items: items,
      avg_item_value_cents: avg_item_value_cents,
      priciest_item: priciest_item,
      rarity_counts: rarity_counts
    )
  end
end
