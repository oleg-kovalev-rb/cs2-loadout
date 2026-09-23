require "rails_helper"

RSpec.describe PriceUpdateWorker do
  subject(:perform) { described_class.new.perform(item_id) }

  before { flush_prices_stream }
  after { flush_prices_stream }

  describe "#perform" do
    context "when the item does not exist" do
      let(:item_id) { -1 }

      it "returns without calling the Steam API" do
        perform

        expect(a_request(:get, %r{steamcommunity\.com/market/priceoverview/})).not_to have_been_made
      end
    end

    context "when the Steam API call succeeds" do
      let(:item_id) { item.id }

      before do
        stub_request(:get, %r{steamcommunity\.com/market/priceoverview/})
          .to_return(
            status: 200,
            body: { success: true, lowest_price: "$38.45", median_price: "$39.00", volume: "1,234" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      context "with no prior price log" do
        let(:item) { create(:item, :without_price) }

        it "creates the first price log, updates the item, and publishes to the stream" do
          perform
          item.reload
          fields = prices_stream_entries.last[1]

          aggregate_failures do
            expect(item.price_logs.count).to eq(1)
            expect(item.price_logs.first.lowest_price_cents).to eq(3845)
            expect(item.current_price_cents).to eq(3845)
            expect(item.change_24h_cents).to eq(0)
            expect(fields["market_hash_name"]).to eq(item.market_hash_name)
            expect(fields["price_cents"]).to eq("3845")
            expect(fields["change_24h_cents"]).to eq("0")
          end
        end
      end

      context "with a price log older than 24h" do
        let(:item) { create(:item, current_price_cents: 3000) }

        before { create(:price_log, :old, item:, lowest_price_cents: 3000) }

        it "computes change_24h_cents against that price log" do
          perform

          item.reload
          expect(item.price_logs.count).to eq(2)
          expect(item.change_24h_cents).to eq(845)

          fields = prices_stream_entries.last[1]
          expect(fields["change_24h_cents"]).to eq("845")
        end
      end
    end

    context "when the Steam API response is unsuccessful" do
      let(:item) { create(:item, current_price_cents: 3845, change_24h_cents: 0) }
      let(:item_id) { item.id }

      before do
        stub_request(:get, %r{steamcommunity\.com/market/priceoverview/})
          .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "does not write a price log, does not touch the item, and does not publish" do
        perform

        item.reload
        expect(item.price_logs.count).to eq(0)
        expect(item.current_price_cents).to eq(3845)
        expect(prices_stream_entries).to be_empty
      end
    end

    context "when the Steam API returns an error status" do
      let(:item) { create(:item, current_price_cents: 3845, change_24h_cents: 0) }
      let(:item_id) { item.id }

      before { stub_request(:get, %r{steamcommunity\.com/market/priceoverview/}).to_return(status: 429) }

      it "does not write a price log, does not touch the item, and does not publish" do
        perform

        item.reload
        expect(item.price_logs.count).to eq(0)
        expect(item.current_price_cents).to eq(3845)
        expect(prices_stream_entries).to be_empty
      end
    end
  end
end
