require "rails_helper"

RSpec.describe InventoryValueUpdateWorker do
  subject(:perform) { described_class.new.perform(steam_id) }

  let(:steam_id) { "76561198000000001" }

  def stub_inventory(market_hash_names)
    stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
      .to_return(
        status: 200,
        body: {
          success: 1,
          assets: market_hash_names.each_index.map { |i| { classid: i.to_s } },
          descriptions: market_hash_names.each_with_index.map { |name, i| { classid: i.to_s, market_hash_name: name } }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#perform" do
    context "when the Steam API call succeeds" do
      context "with priced items" do
        let(:priced_item) { create(:item, current_price_cents: 3845) }
        let(:other_priced_item) { create(:item, current_price_cents: 1200) }

        before { stub_inventory([ priced_item.market_hash_name, other_priced_item.market_hash_name ]) }

        it "writes today's log entry with the summed total" do
          perform

          log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

          expect(log.total_value_cents).to eq(5045)
        end
      end

      context "with an item that has no price yet" do
        let(:unpriced_item) { create(:item, :without_price) }

        before { stub_inventory([ unpriced_item.market_hash_name ]) }

        it "counts it as 0" do
          perform

          log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

          expect(log.total_value_cents).to eq(0)
        end
      end

      context "with an item that has no Item row at all" do
        before { stub_inventory([ "AK-47 | Totally Unknown (Field-Tested)" ]) }

        it "counts it as 0 without error" do
          perform

          log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

          expect(log.total_value_cents).to eq(0)
        end
      end

      context "when a log entry for this steam_id/day already exists" do
        let(:priced_item) { create(:item, current_price_cents: 3845) }

        before do
          create(:inventory_value_log, steam_id: steam_id, log_date: Date.current, total_value_cents: 1)
          stub_inventory([ priced_item.market_hash_name ])
        end

        it "updates the existing row in place instead of creating a second one" do
          perform

          expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current).count).to eq(1)
          expect(InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current).total_value_cents).to eq(3845)
        end
      end
    end

    context "when the Steam API response is unsuccessful" do
      before do
        stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
          .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "does not write a log entry" do
        perform

        expect(InventoryValueLog.where(steam_id: steam_id)).to be_empty
      end
    end
  end
end
