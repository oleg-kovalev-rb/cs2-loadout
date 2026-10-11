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
        :items_count, :rarity_mix_percent, :last_synced_at
      )
    end

    it "computes change_24h_percent from total_value_cents and change_24h_cents" do
      page = page_with(build_summary(total_value_cents: 1500, change_24h_cents: 500))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:change_24h_percent]).to be_within(0.01).of(50.0)
    end

    it "defaults change_24h_percent to 0.0 when the base value is zero" do
      page = page_with(build_summary(total_value_cents: 0, change_24h_cents: 0))

      inventory_json = described_class.call(page)[:inventories].first

      expect(inventory_json[:change_24h_percent]).to eq(0.0)
    end

    it "computes rarity_mix_percent against the classified item count, not items_count" do
      page = page_with(build_summary(
        items_count: 5,
        rarity_counts: { RarityTier::Covert => 1, RarityTier::Classified => 3 }
      ))

      rarity_mix_percent = described_class.call(page)[:inventories].first[:rarity_mix_percent]

      aggregate_failures do
        expect(rarity_mix_percent.keys).to contain_exactly(
          :gold, :covert, :classified, :restricted, :mil_spec, :industrial, :consumer
        )
        expect(rarity_mix_percent[:covert]).to be_within(0.01).of(25.0)
        expect(rarity_mix_percent[:classified]).to be_within(0.01).of(75.0)
        expect(rarity_mix_percent[:gold]).to eq(0.0)
      end
    end

    it "returns all-zero rarity_mix_percent when nothing classified" do
      page = page_with(build_summary(rarity_counts: {}))

      rarity_mix_percent = described_class.call(page)[:inventories].first[:rarity_mix_percent]

      expect(rarity_mix_percent.values).to all(eq(0.0))
    end
  end

  def build_summary(steam_id: "76561198000000001", items_count: 0, total_value_cents: 0,
                     change_24h_cents: 0, last_synced_at: "2024-01-01T00:00:00Z", rarity_counts: {})
    InventoryCatalogQuery::InventorySummary.new(
      steam_id: steam_id, items_count: items_count, total_value_cents: total_value_cents,
      change_24h_cents: change_24h_cents, last_synced_at: last_synced_at, rarity_counts: rarity_counts
    )
  end

  def page_with(summary)
    InventoryCatalogQuery::Page.new(inventories: [ summary ], pagination: Appliers::Pagination.new(nil, nil), total_count: 1)
  end
end
