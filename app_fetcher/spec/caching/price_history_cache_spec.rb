require "rails_helper"

RSpec.describe PriceHistoryCache do
  let!(:redline) { create(:item) }
  let!(:recent_log) { create(:price_log, item: redline, created_at: 1.hour.ago, lowest_price_cents: 3845, volume: 512) }

  describe ".fetch_for" do
    it "hits the DB once on a cold cache and returns points keyed by market_hash_name" do
      result = nil
      queries = count_queries(model: PriceLog) { result = described_class.fetch_for([ redline.market_hash_name ]) }

      aggregate_failures do
        expect(queries).to eq(1)
        expect(result[redline.market_hash_name]).to contain_exactly(
          { at: recent_log.created_at.iso8601, price_cents: 3845, volume: 512 }
        )
      end
    end

    it "does not hit the DB on a warm cache" do
      described_class.fetch_for([ redline.market_hash_name ])

      queries = count_queries(model: PriceLog) { described_class.fetch_for([ redline.market_hash_name ]) }

      expect(queries).to eq(0)
    end

    it "excludes points older than the default 30-day window" do
      create(:price_log, item: redline, created_at: 31.days.ago)

      result = described_class.fetch_for([ redline.market_hash_name ])

      expect(result[redline.market_hash_name].size).to eq(1)
    end

    it "returns an empty array for an item with no price logs, and omits names with no Item row" do
      other_item = create(:item)

      result = described_class.fetch_for([ other_item.market_hash_name, "does not exist" ])

      expect(result).to eq(other_item.market_hash_name => [])
    end
  end

  describe ".invalidate" do
    it "deletes the cached entry so a subsequent fetch_for is a genuine miss" do
      described_class.fetch_for([ redline.market_hash_name ])

      described_class.invalidate(redline.market_hash_name)

      queries = count_queries(model: PriceLog) { described_class.fetch_for([ redline.market_hash_name ]) }

      expect(queries).to eq(1)
    end
  end
end
