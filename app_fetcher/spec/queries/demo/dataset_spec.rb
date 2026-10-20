require "rails_helper"

RSpec.describe Demo::Dataset do
  subject(:dataset) { described_class.new }

  let(:first_name) { "Demo | First Skin (Field-Tested)" }
  let(:second_name) { "Demo | Second Skin (Factory New)" }

  let(:first_entry) do
    Demo::Inventory::Entry.new(market_hash_name: first_name, base_price_cents: 1_000)
  end
  let(:second_entry) do
    Demo::Inventory::Entry.new(market_hash_name: second_name, base_price_cents: 2_500)
  end

  let(:pool_entries) do
    [
      {
        "market_hash_name" => first_name,
        "rarity" => "Classified",
        "category" => "Rifle",
        "icon_url" => "https://community.akamai.steamstatic.com/economy/image/first"
      },
      {
        "market_hash_name" => second_name,
        "rarity" => "Covert",
        "category" => "Pistol",
        "icon_url" => "https://community.akamai.steamstatic.com/economy/image/second"
      }
    ]
  end

  before do
    allow(Demo::Inventory).to receive(:entries).and_return([ first_entry, second_entry ])
    allow(Demo::ItemPool).to receive(:entries).and_return(pool_entries)
  end

  describe "#items" do
    it "always builds the same fixed item set" do
      first = described_class.new.items.map(&:market_hash_name)
      second = described_class.new.items.map(&:market_hash_name)

      expect(first).to eq([ first_name, second_name ])
      expect(second).to eq(first)
    end

    it "uses pool metadata rather than the live Item metadata" do
      create(
        :item,
        market_hash_name: first_name,
        current_price_cents: 12_345,
        metadata: { marketable: true, rarity: "Consumer Grade", category: "SMG", icon_url: nil }
      )

      item = dataset.items.first

      aggregate_failures do
        expect(item.rarity).to eq("Classified")
        expect(item.category).to eq("Rifle")
        expect(item.icon_url).to eq("https://community.akamai.steamstatic.com/economy/image/first")
      end
    end

    it "uses a real current price as the anchor, rounded to a whole dollar" do
      create(
        :item,
        market_hash_name: first_name,
        current_price_cents: 12_345,
        price_updated_at: Time.current,
        metadata: { marketable: true }
      )

      aggregate_failures do
        expect(dataset.items.first.current_price_cents).to eq(12_300)
        expect(dataset.items.last.current_price_cents).to eq(2_500)
      end
    end

    it "falls back to the YAML base price when the real item is unavailable" do
      create(
        :item,
        market_hash_name: first_name,
        current_price_cents: 99_999,
        price_unavailable: true,
        metadata: { marketable: true }
      )

      expect(dataset.items.first.current_price_cents).to eq(1_000)
    end
  end

  describe "#value" do
    it "sums the item series into the portfolio history" do
      first_item = dataset.items.first
      second_item = dataset.items.last
      first_history = dataset.history(first_item, period: "7d").points
      second_history = dataset.history(second_item, period: "7d").points
      portfolio = dataset.value(period: "7d").history.points

      expected = first_history.each_index.map do |index|
        first_history.fetch(index).price_cents + second_history.fetch(index).price_cents
      end

      aggregate_failures do
        expect(portfolio.map(&:total_value_cents)).to eq(expected)
        expect(portfolio.last.total_value_cents).to eq(3_500)
        expect(portfolio.last.complete).to be(true)
      end
    end

    it "makes the current price equal the last item history point" do
      item = dataset.items.first
      history = dataset.history(item, period: "7d").points

      expect(history.last.price_cents).to eq(item.current_price_cents)
    end
  end

  describe "#summary" do
    it "uses the generated snapshot and delta" do
      summary = dataset.summary

      aggregate_failures do
        expect(summary.steam_id).to eq("demo")
        expect(summary.snapshot.total_value_cents).to eq(3_500)
        expect(summary.snapshot.complete?).to be(true)
        expect(summary.rarity_counts.values.sum).to eq(2)
      end
    end
  end

  describe "#details" do
    it "supports every sort option" do
      first_item = dataset.items.first
      expected_changes = dataset.items.sort_by { |item| -(item.change_24h_cents || 0) }.map(&:market_hash_name)

      { "price_desc" => [ second_name, first_name ],
        "price_asc" => [ first_name, second_name ],
        "name_asc" => [ first_name, second_name ],
        "change_24h_desc" => expected_changes }.each do |sort, expected|
        details = dataset.details(
          ActionController::Parameters.new(sort: sort, per_page: 10, period: "7d")
        )

        expect(details.items.entries.map(&:market_hash_name)).to eq(expected)
      end
    end

    it "honors period and pagination" do
      details = dataset.details(
        ActionController::Parameters.new(period: "7d", sort: "price_desc", page: 2, per_page: 1)
      )

      aggregate_failures do
        expect(details.range).to eq(Options::DateRange::Last7Days)
        expect(details.items.entries.map(&:market_hash_name)).to eq([ first_name ])
        expect(details.items.total_count).to eq(2)
        expect(details.items.pagination.total_pages(2)).to eq(2)
        expect(details.avg_item_value_cents).to eq(1_800)
        expect(details.priciest_item&.market_hash_name).to eq(second_name)
      end
    end

    it "rejects an unsupported sort" do
      expect {
        dataset.details(ActionController::Parameters.new(sort: "unknown"))
      }.to raise_error(Api::Demo::UnsupportedParamError, "Unsupported sort: unknown")
    end
  end

  describe "#trends" do
    it "returns five points per item ending at the current price" do
      trends = dataset.trends
      item = dataset.items.first

      aggregate_failures do
        expect(trends.keys).to contain_exactly(first_name, second_name)
        expect(trends.fetch(first_name).size).to eq(5)
        expect(trends.fetch(first_name).last[:price_cents]).to eq(item.current_price_cents)
      end
    end
  end

  describe "#history" do
    it "supports the demo history ranges" do
      item = dataset.items.first

      aggregate_failures do
        expect(dataset.history(item, period: "24h").points.size).to eq(24)
        expect(dataset.history(item, period: "30d").points.size).to eq(30)
        expect(dataset.history(item, period: "1y").points.size).to eq(365)
      end
    end

    it "raises for an unknown item" do
      expect { dataset.item!("Unknown Item") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "does not write domain rows" do
    expect {
      dataset.items
      dataset.value(period: "7d")
      dataset.details(ActionController::Parameters.new(period: "7d"))
    }.not_to change { [ PriceLog.count, InventoryValueLog.count, UserInventory.count ] }
  end
end
