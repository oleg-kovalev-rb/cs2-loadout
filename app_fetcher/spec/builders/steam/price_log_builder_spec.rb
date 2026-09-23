require "rails_helper"

RSpec.describe Steam::PriceLogBuilder do
  describe ".build" do
    it "converts a fully-populated price DTO into cents/volume and keeps the item_id" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "$38.45",
        median_price: "$39,00",
        volume: "1,234"
      )

      price_log = described_class.build(42, price_data)

      aggregate_failures do
        expect(price_log.item_id).to eq(42)
        expect(price_log.lowest_price_cents).to eq(3845)
        expect(price_log.median_price_cents).to eq(3900)
        expect(price_log.volume).to eq(1234)
        expect(price_log.persisted?).to eq(false)
      end
    end

    it "returns zero for nil price/volume fields" do
      price_data = Steam::Response::Data::ItemPriceData.new(lowest_price: nil, median_price: nil, volume: nil)

      price_log = described_class.build(1, price_data)

      expect(price_log.lowest_price_cents).to eq(0)
      expect(price_log.median_price_cents).to eq(0)
      expect(price_log.volume).to eq(0)
    end

    it "returns zero for empty-string price/volume fields" do
      price_data = Steam::Response::Data::ItemPriceData.new(lowest_price: "", median_price: "", volume: "")

      price_log = described_class.build(1, price_data)

      expect(price_log.lowest_price_cents).to eq(0)
      expect(price_log.median_price_cents).to eq(0)
      expect(price_log.volume).to eq(0)
    end
  end
end
