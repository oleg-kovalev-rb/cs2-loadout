require "rails_helper"

RSpec.describe InventoryListSerializer do
  describe ".call" do
    it "builds the meta hash from the result's pagination and total_count" do
      result = InventoryListQuery::InventorySummaries.new(
        inventories: [],
        pagination: Appliers::Pagination.new("2", "10"),
        total_count: 25
      )

      expect(described_class.call(result)[:meta]).to eq(page: 2, per_page: 10, total_count: 25, total_pages: 3)
    end

    it "exposes exactly the contracted inventory keys" do
      inventory_json = described_class.call(result_with(build_summary))[:inventories].first

      expect(inventory_json.keys).to contain_exactly(
        :steam_id, :total_value_cents, :change_24h_cents, :change_24h_percent,
        :items_count, :pricable_items_count, :priced_items_count, :complete,
        :change_basis_at, :change_partial, :change_available,
        :rarity_breakdown, :last_synced_at
      )
    end

    it "passes the snapshot/delta values through and formats dates" do
      summary = build_summary(
        total_value_cents: 1500,
        items_count: 3,
        pricable_items_count: 3,
        priced_items_count: 3,
        change_cents: 500,
        change_percent: 50.0,
        change_basis_at: Time.utc(2024, 1, 1),
        change_partial: false,
        change_available: true,
        last_synced_at: Time.utc(2024, 1, 2, 3, 4, 5)
      )

      inventory_json = described_class.call(result_with(summary))[:inventories].first

      expect(inventory_json).to include(
        total_value_cents: 1500,
        items_count: 3,
        change_24h_cents: 500,
        change_24h_percent: 50.0,
        change_basis_at: "2024-01-01",
        change_partial: false,
        change_available: true,
        last_synced_at: "2024-01-02T03:04:05Z"
      )
    end

    it "derives complete from the snapshot's priced/pricable counts" do
      complete = build_summary(pricable_items_count: 2, priced_items_count: 2)
      incomplete = build_summary(pricable_items_count: 2, priced_items_count: 1)

      expect(described_class.call(result_with(complete))[:inventories].first[:complete]).to be(true)
      expect(described_class.call(result_with(incomplete))[:inventories].first[:complete]).to be(false)
    end

    it "builds rarity_breakdown against the classified item count, not items_count" do
      summary = build_summary(
        items_count: 5,
        rarity_counts: { RarityTier::Covert => 1, RarityTier::Classified => 3 }
      )

      rarity_breakdown = described_class.call(result_with(summary))[:inventories].first[:rarity_breakdown]
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

    it "returns all-zero rarity_breakdown when nothing classified" do
      summary = build_summary(rarity_counts: {})

      rarity_breakdown = described_class.call(result_with(summary))[:inventories].first[:rarity_breakdown]

      expect(rarity_breakdown.map { |entry| entry[:percent] }).to all(eq(0.0))
    end
  end

  def build_summary(steam_id: "76561198000000001", items_count: 0, total_value_cents: 0,
                    pricable_items_count: 0, priced_items_count: 0, change_cents: 0,
                    change_percent: 0.0, change_basis_at: nil, change_partial: false,
                    change_available: false, last_synced_at: Time.utc(2024, 1, 1), rarity_counts: {})
    InventoryListQuery::InventorySummary.new(
      steam_id: steam_id,
      snapshot: InventoryValueQuery::ValueSnapshot.new(
        total_value_cents: total_value_cents,
        items_count: items_count,
        pricable_items_count: pricable_items_count,
        priced_items_count: priced_items_count,
        oldest_price_at: nil
      ),
      delta: InventoryValueQuery::ValueDelta.new(
        cents: change_cents,
        percent: change_percent,
        basis_at: change_basis_at,
        partial: change_partial,
        available: change_available
      ),
      last_synced_at: last_synced_at,
      rarity_counts: rarity_counts
    )
  end

  def result_with(summary)
    InventoryListQuery::InventorySummaries.new(
      inventories: [ summary ],
      pagination: Appliers::Pagination.new(nil, nil),
      total_count: 1
    )
  end
end
