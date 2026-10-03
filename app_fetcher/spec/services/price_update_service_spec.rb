require "rails_helper"

RSpec.describe PriceUpdateService do
  let(:price_data) do
    Steam::Response::Data::ItemPriceData.new(
      lowest_price: "$38.45",
      median_price: "$39.00",
      volume: "1,234"
    )
  end

  describe ".call" do
    context "with no prior price log" do
      let(:item) { create(:item, :without_price) }

      it "creates the first price log, updates the item, and returns a result with change_24h_cents of 0" do
        result = described_class.call(item, price_data)
        item.reload

        aggregate_failures do
          expect(result.success).to be(true)
          expect(result.price_log).to be_persisted
          expect(result.price_log.lowest_price_cents).to eq(3845)
          expect(result.item.current_price_cents).to eq(3845)
          expect(result.change_24h_cents).to eq(0)
          expect(item.current_price_cents).to eq(3845)
          expect(item.change_24h_cents).to eq(0)
        end
      end
    end

    context "with a price log older than 24h" do
      let(:item) { create(:item, current_price_cents: 3000) }

      before { create(:price_log, :old, item:, lowest_price_cents: 3000) }

      it "computes change_24h_cents against that price log" do
        result = described_class.call(item, price_data)

        aggregate_failures do
          expect(result.success).to be(true)
          expect(result.change_24h_cents).to eq(845)
          expect(item.price_logs.count).to eq(2)
        end
      end
    end
  end
end
