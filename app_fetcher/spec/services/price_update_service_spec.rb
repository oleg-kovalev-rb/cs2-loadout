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

      it "creates the first price log, updates the item, and computes change_24h_cents of 0" do
        described_class.call(item, price_data)
        item.reload

        aggregate_failures do
          expect(item.price_logs.last).to be_persisted
          expect(item.price_logs.last.lowest_price_cents).to eq(3845)
          expect(item.current_price_cents).to eq(3845)
          expect(item.change_24h_cents).to eq(0)
          expect(item.price_updated_at).to be_within(1.second).of(Time.current)
        end
      end

      it "returns an ApplicationService::Result with a Success status carrying the updated Item" do
        result = described_class.call(item, price_data)

        aggregate_failures do
          expect(result.success?).to be(true)
          expect(result.data).to eq(item)
          expect(result.error).to be_nil
        end
      end
    end

    context "with a single prior price log younger than 24h" do
      let(:item) { create(:item, current_price_cents: 3000) }

      before { create(:price_log, item:, lowest_price_cents: 3000, created_at: 3.hours.ago) }

      it "computes change_24h_cents against that log" do
        described_class.call(item, price_data)

        expect(item.change_24h_cents).to eq(845)
      end
    end

    context "with multiple prior price logs all younger than 24h" do
      let(:item) { create(:item, current_price_cents: 3500) }

      before do
        create(:price_log, item:, lowest_price_cents: 3000, created_at: 3.hours.ago)
        create(:price_log, item:, lowest_price_cents: 3500, created_at: 1.hour.ago)
      end

      it "uses the oldest log as the baseline, not the most recent one" do
        described_class.call(item, price_data)

        expect(item.change_24h_cents).to eq(845)
      end
    end

    context "with a price log older than 24h" do
      let(:item) { create(:item, current_price_cents: 3000) }

      before { create(:price_log, :old, item:, lowest_price_cents: 3000) }

      it "computes change_24h_cents against that price log" do
        described_class.call(item, price_data)

        aggregate_failures do
          expect(item.change_24h_cents).to eq(845)
          expect(item.price_logs.count).to eq(2)
        end
      end
    end

    context "when the item was previously marked price_unavailable" do
      let(:item) { create(:item, :without_price, :price_unavailable) }

      it "clears the price_unavailable flag" do
        described_class.call(item, price_data)

        expect(item.reload.price_unavailable).to be(false)
      end
    end
  end
end
