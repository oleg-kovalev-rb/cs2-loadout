require "rails_helper"

RSpec.describe PriceLogBuilder do
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

    it "parses US-formatted prices with thousands separators" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "$1,234.56",
        median_price: "$12,345.67",
        volume: "1,234"
      )

      price_log = described_class.build(7, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(123_456)
        expect(price_log.median_price_cents).to eq(1_234_567)
      end
    end

    it "parses European-formatted prices with thousands separators" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "1.234,56€",
        median_price: "12.345,67€",
        volume: "1"
      )

      price_log = described_class.build(8, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(123_456)
        expect(price_log.median_price_cents).to eq(1_234_567)
      end
    end

    it "parses whole-currency amounts with thousands separators" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "$1,234",
        median_price: "$1,234,567",
        volume: "1"
      )

      price_log = described_class.build(9, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(123_400)
        expect(price_log.median_price_cents).to eq(123_456_700)
      end
    end

    it "parses plain whole-currency amounts" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "$1234",
        median_price: "$1.234",
        volume: "1"
      )

      price_log = described_class.build(10, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(123_400)
        expect(price_log.median_price_cents).to eq(123_400)
      end
    end

    it "strips space thousands separators, including non-breaking spaces" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "1 234,56€",
        median_price: "1\u00A0234,56€",
        volume: "1"
      )

      price_log = described_class.build(11, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(123_456)
        expect(price_log.median_price_cents).to eq(123_456)
      end
    end

    it "rounds fractional cents with integer arithmetic" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "$1,234.567",
        median_price: "$1.234,567",
        volume: "1"
      )

      price_log = described_class.build(12, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(123_457)
        expect(price_log.median_price_cents).to eq(123_457)
      end
    end

    it "returns zero when the price contains no digits" do
      price_data = Steam::Response::Data::ItemPriceData.new(
        lowest_price: "N/A",
        median_price: "—",
        volume: "1"
      )

      price_log = described_class.build(13, price_data)

      aggregate_failures do
        expect(price_log.lowest_price_cents).to eq(0)
        expect(price_log.median_price_cents).to eq(0)
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
