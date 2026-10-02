require "rails_helper"

RSpec.describe UserInventorySyncService do
  subject(:call) { described_class.call(steam_id) }

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

  context "when the Steam call succeeds" do
    context "with all names already known" do
      let(:known_item) { create(:item) }

      before { stub_inventory([ known_item.market_hash_name ]) }

      it "does not create a new Item and syncs the existing one" do
        call

        aggregate_failures do
          expect(call.success).to be(true)
          expect(call.items).to contain_exactly(known_item)
          expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(known_item)
        end
      end
    end

    context "with a mix of known and unknown names" do
      let(:known_item) { create(:item) }
      let(:unknown_name) { "AK-47 | Totally Unknown (Field-Tested)" }

      before { stub_inventory([ known_item.market_hash_name, unknown_name ]) }

      it "backfills the unknown Item and includes it in the synced set" do
        call

        backfilled = Item.find_by(market_hash_name: unknown_name)

        aggregate_failures do
          expect(call.success).to be(true)
          expect(backfilled).to be_present
          expect(call.items).to contain_exactly(known_item, backfilled)
          expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(known_item, backfilled)
        end
      end
    end

    context "on a second call with a different item set" do
      let(:first_item) { create(:item) }
      let(:second_item) { create(:item) }

      it "fully replaces the prior synced item set" do
        stub_inventory([ first_item.market_hash_name ])
        described_class.call(steam_id)

        stub_inventory([ second_item.market_hash_name ])
        described_class.call(steam_id)

        expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(second_item)
      end

      it "invalidates any previously cached UserInventoryCache entry" do
        stub_inventory([ first_item.market_hash_name ])
        described_class.call(steam_id)
        UserInventoryCache.fetch(steam_id)

        stub_inventory([ second_item.market_hash_name ])
        described_class.call(steam_id)

        expect(UserInventoryCache.fetch(steam_id)).to contain_exactly(second_item)
      end
    end
  end

  context "when the Steam call fails" do
    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "returns a failure Result and does not touch the DB" do
      call

      aggregate_failures do
        expect(call.success).to be(false)
        expect(call.error).to be_present
        expect(UserInventory.find_by(steam_id: steam_id)).to be_nil
      end
    end
  end
end
