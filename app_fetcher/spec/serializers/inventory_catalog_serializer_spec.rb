require "rails_helper"

RSpec.describe InventoryCatalogSerializer do
  describe ".call" do
    it "builds the meta hash from the page's pagination and total_count" do
      page = InventoryCatalogQuery::Page.new(
        inventories: [],
        pagination: Appliers::Pagination.new("2", "10"),
        total_count: 25
      )

      result = described_class.call(page)

      expect(result[:meta]).to eq(page: 2, per_page: 10, total_count: 25, total_pages: 3)
    end

    it "exposes exactly the contracted inventory keys" do
      page = page_with(build_summary)

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json.keys).to contain_exactly(
        :steam_id, :total_value_cents, :change_24h_cents, :change_24h_percent,
        :items_count, :pricable_items_count, :priced_items_count, :complete,
        :change_basis_at, :change_partial, :change_available,
        :rarity_breakdown, :last_synced_at
      )
    end

    it "computes change_24h_percent from total_value_cents and change_24h_cents" do
      page = page_with(build_summary(total_value_cents: 1500, change_24h_cents: 500, change_available: true))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:change_24h_percent]).to be_within(0.01).of(50.0)
    end

    it "defaults change_24h_percent to 0.0 when the base value is zero" do
      page = page_with(build_summary(total_value_cents: 0, change_24h_cents: 0, change_available: true))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:change_24h_percent]).to eq(0.0)
    end

    it "defaults change_24h_percent to 0.0 when the change is unavailable" do
      page = page_with(build_summary(total_value_cents: 1500, change_24h_cents: 500, change_available: false))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:change_24h_percent]).to eq(0.0)
    end

    it "derives complete from the priced/pricable counts" do
      page = page_with(build_summary(pricable_items_count: 2, priced_items_count: 2))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:complete]).to be(true)
    end

    it "reports an incomplete card when a pricable item is unpriced" do
      page = page_with(build_summary(pricable_items_count: 2, priced_items_count: 1))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:complete]).to be(false)
    end

    it "builds rarity_breakdown against the classified item count, not items_count" do
      page = page_with(build_summary(
        items_count: 5,
        rarity_counts: { RarityTier::Covert => 1, RarityTier::Classified => 3 }
      ))

      rarity_breakdown = described_class.call(page)[:inventories].first[:rarity_breakdown]
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
      page = page_with(build_summary(rarity_counts: {}))

      rarity_breakdown = described_class.call(page)[:inventories].first[:rarity_breakdown]

      expect(rarity_breakdown.map { |entry| entry[:percent] }).to all(eq(0.0))
    end
  end

  def build_summary(steam_id: "76561198000000001", items_count: 0, total_value_cents: 0,
                     pricable_items_count: 0, priced_items_count: 0, change_24h_cents: 0,
                     change_basis_at: nil, change_partial: false, change_available: false,
                     oldest_price_at: nil, last_synced_at: "2024-01-01T00:00:00Z", rarity_counts: {})
    InventoryCatalogQuery::InventorySummary.new(
      steam_id: steam_id, items_count: items_count, total_value_cents: total_value_cents,
      pricable_items_count: pricable_items_count, priced_items_count: priced_items_count,
      oldest_price_at: oldest_price_at, change_24h_cents: change_24h_cents,
      change_basis_at: change_basis_at, change_partial: change_partial,
      change_available: change_available, last_synced_at: last_synced_at, rarity_counts: rarity_counts
    )
  end

  def page_with(summary)
    InventoryCatalogQuery::Page.new(inventories: [ summary ], pagination: Appliers::Pagination.new(nil, nil), total_count: 1)
  end
end
