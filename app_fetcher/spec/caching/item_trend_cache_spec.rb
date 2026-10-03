require "rails_helper"

RSpec.describe ItemTrendCache do
  let(:item) { create(:item) }

  describe ".fetch_for" do
    it "hits the DB once on a cold cache and returns downsampled points spanning the 7-day window" do
      create(:price_log, item: item, lowest_price_cents: 1000, volume: 1, created_at: 6.days.ago)
      create(:price_log, item: item, lowest_price_cents: 1500, volume: 2, created_at: 4.days.ago)
      create(:price_log, item: item, lowest_price_cents: 2000, volume: 3, created_at: 2.days.ago)
      create(:price_log, item: item, lowest_price_cents: 2500, volume: 4, created_at: 1.hour.ago)

      result = nil
      queries = count_queries(model: PriceLog) { result = described_class.fetch_for([ item.market_hash_name ]) }

      points = result[item.market_hash_name]

      aggregate_failures do
        expect(queries).to eq(1)
        expect(points.size).to be <= 5
        expect(points.last[:price_cents]).to eq(2500)
        expect(points.first).to include(:at, :price_cents, :volume)
      end
    end

    it "does not hit the DB on a warm cache" do
      create(:price_log, item: item, created_at: 1.day.ago)
      described_class.fetch_for([ item.market_hash_name ])

      queries = count_queries(model: PriceLog) { described_class.fetch_for([ item.market_hash_name ]) }

      expect(queries).to eq(0)
    end

    it "omits a name with no matching Item row" do
      result = described_class.fetch_for([ "does not exist" ])

      expect(result).to eq({})
    end

    it "omits an owned item with zero PriceLog rows in the window" do
      result = described_class.fetch_for([ item.market_hash_name ])

      expect(result).to eq({})
    end

    it "returns exactly as many distinct points as exist, not padded to 5" do
      create(:price_log, item: item, lowest_price_cents: 1000, volume: 1, created_at: 6.days.ago)
      create(:price_log, item: item, lowest_price_cents: 1200, volume: 2, created_at: 5.days.ago)

      points = described_class.fetch_for([ item.market_hash_name ])[item.market_hash_name]

      aggregate_failures do
        expect(points.size).to eq(2)
        expect(points.map { |p| p[:price_cents] }).to eq([ 1000, 1200 ])
      end
    end

    it "excludes logs older than the 7-day window" do
      create(:price_log, item: item, lowest_price_cents: 999, created_at: 10.days.ago)
      create(:price_log, item: item, lowest_price_cents: 1234, created_at: 1.day.ago)

      points = described_class.fetch_for([ item.market_hash_name ])[item.market_hash_name]

      expect(points.map { |p| p[:price_cents] }).to eq([ 1234 ])
    end
  end

  describe ".invalidate" do
    it "deletes the cached entry so a subsequent fetch_for is a genuine miss" do
      create(:price_log, item: item, created_at: 1.day.ago)
      described_class.fetch_for([ item.market_hash_name ])

      described_class.invalidate(item.market_hash_name)

      queries = count_queries(model: PriceLog) { described_class.fetch_for([ item.market_hash_name ]) }

      expect(queries).to eq(1)
    end
  end
end
