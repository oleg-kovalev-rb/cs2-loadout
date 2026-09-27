require "rails_helper"

RSpec.describe ItemPriceCache do
  let!(:redline) { create(:item, current_price_cents: 3845, change_24h_cents: 120) }
  let!(:vulcan) { create(:item, current_price_cents: 9999, change_24h_cents: -50) }

  describe ".fetch_for" do
    it "hits the DB once on a cold cache and returns items keyed by market_hash_name" do
      result = nil
      queries = count_queries(model: Item) { result = described_class.fetch_for([ redline.market_hash_name, vulcan.market_hash_name ]) }

      aggregate_failures do
        expect(queries).to eq(1)
        expect(result[redline.market_hash_name].current_price_cents).to eq(3845)
        expect(result[vulcan.market_hash_name].current_price_cents).to eq(9999)
      end
    end

    it "does not hit the DB on a warm cache" do
      described_class.fetch_for([ redline.market_hash_name ])

      queries = count_queries(model: Item) { described_class.fetch_for([ redline.market_hash_name ]) }

      expect(queries).to eq(0)
    end

    it "omits names with no matching Item row" do
      result = described_class.fetch_for([ "does not exist" ])

      expect(result).to eq({})
    end
  end

  describe ".invalidate" do
    it "deletes the cached entry so a subsequent fetch_for is a genuine miss" do
      described_class.fetch_for([ redline.market_hash_name ])

      described_class.invalidate(redline.market_hash_name)

      queries = count_queries(model: Item) { described_class.fetch_for([ redline.market_hash_name ]) }

      expect(queries).to eq(1)
    end
  end
end
