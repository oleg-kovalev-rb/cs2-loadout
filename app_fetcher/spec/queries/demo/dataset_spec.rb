require "rails_helper"

RSpec.describe Demo::Dataset do
  let!(:cheap_item) do
    create(
      :item,
      market_hash_name: "Demo | Cheap (Field-Tested)",
      current_price_cents: 100,
      price_updated_at: Time.current,
      metadata: { marketable: true, rarity: "Consumer Grade", category: "Pistol" }
    )
  end
  let!(:expensive_item) do
    create(
      :item,
      market_hash_name: "Demo | Expensive (Factory New)",
      current_price_cents: 10_000,
      price_updated_at: Time.current,
      metadata: { marketable: true, rarity: "Covert", category: "Rifle" }
    )
  end

  before do
    stub_const("Demo::Dataset::ITEM_COUNT", 2)
    allow(Demo::ItemPool).to receive(:market_hash_names)
      .and_return([ cheap_item.market_hash_name, expensive_item.market_hash_name ])
  end

  describe "#items" do
    it "is deterministic for the same seed" do
      first = described_class.new(seed: 123).items
      second = described_class.new(seed: 123).items

      expect(first.map(&:id)).to eq(second.map(&:id))
    end

    it "falls back to priced marketable items when the pool has no matches" do
      allow(Demo::ItemPool).to receive(:market_hash_names).and_return([ "Missing | Item" ])

      items = described_class.new(seed: 123).items

      expect(items.map(&:id)).to include(cheap_item.id, expensive_item.id)
    end
  end

  describe "#value" do
    it "generates a complete history ending at the current total" do
      dataset = described_class.new(seed: 123)

      value = dataset.value(period: "7d")

      aggregate_failures do
        expect(value.snapshot&.complete?).to be(true)
        expect(value.history.points.last&.total_value_cents).to eq(10_100)
        expect(value.history.points.size).to be > 1
      end
    end

    it "produces different synthetic histories for different seeds" do
      first = described_class.new(seed: 123).value(period: "7d").history.points
      second = described_class.new(seed: 456).value(period: "7d").history.points

      expect(first.map(&:total_value_cents)).not_to eq(second.map(&:total_value_cents))
    end
  end

  describe "#summary" do
    it "returns an inventory summary with rarity counts" do
      summary = described_class.new(seed: 123).summary

      aggregate_failures do
        expect(summary.steam_id).to eq("demo")
        expect(summary.snapshot.total_value_cents).to eq(10_100)
        expect(summary.rarity_counts.values.sum).to eq(2)
      end
    end
  end

  describe "#details" do
    it "honors period, sort, and pagination" do
      params = ActionController::Parameters.new(period: "7d", sort: "price_asc", page: 1, per_page: 1)

      details = described_class.new(seed: 123).details(params)

      aggregate_failures do
        expect(details.range).to eq(Options::DateRange::Last7Days)
        expect(details.items.entries.map(&:id)).to eq([ cheap_item.id ])
        expect(details.items.total_count).to eq(2)
        expect(details.items.pagination.total_pages(2)).to eq(2)
        expect(details.priciest_item&.id).to eq(expensive_item.id)
      end
    end
  end
end
