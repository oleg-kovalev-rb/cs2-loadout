require "rails_helper"

RSpec.describe ItemPriceDynamicsSerializer do
  describe ".call" do
    let(:priced_item) do
      Item.new(
        market_hash_name: "AK-47 | Redline (Field-Tested)",
        current_price_cents: 15_050,
        change_24h_cents: 520,
        price_updated_at: Time.utc(2024, 1, 1, 12, 0, 0)
      )
    end
    let(:unpriced_item) do
      Item.new(market_hash_name: "unpriced", current_price_cents: nil, change_24h_cents: nil)
    end
    let(:priced_items) do
      {
        priced_item.market_hash_name => priced_item,
        unpriced_item.market_hash_name => unpriced_item
      }
    end

    it "shapes priced items, omits unpriced ones, and passes pending_count through" do
      result = described_class.call(priced_items, 1)

      expect(result).to eq(
        prices: {
          priced_item.market_hash_name => {
            current_price_cents: 15_050,
            change_24h_cents: 520,
            change_24h_percent: 3.58,
            price_updated_at: "2024-01-01T12:00:00Z"
          }
        },
        pending_count: 1
      )
    end

    it "returns 0.0 percent when the base price is zero" do
      item = Item.new(market_hash_name: "x", current_price_cents: 500, change_24h_cents: 500)

      result = described_class.call({ item.market_hash_name => item }, 0)

      expect(result[:prices][item.market_hash_name][:change_24h_percent]).to eq(0.0)
    end

    it "treats a nil change as zero and keeps price_updated_at nil when unknown" do
      item = Item.new(market_hash_name: "x", current_price_cents: 700, change_24h_cents: nil, price_updated_at: nil)

      result = described_class.call({ item.market_hash_name => item }, 0)

      aggregate_failures do
        expect(result[:prices][item.market_hash_name][:change_24h_cents]).to eq(0)
        expect(result[:prices][item.market_hash_name][:change_24h_percent]).to eq(0.0)
        expect(result[:prices][item.market_hash_name][:price_updated_at]).to be_nil
      end
    end

    it "returns empty prices and a zero count for an empty input" do
      expect(described_class.call({}, 0)).to eq(prices: {}, pending_count: 0)
    end
  end
end
