require "rails_helper"

RSpec.describe UserInventorySyncWorker do
  subject(:perform) { described_class.new.perform(steam_id) }

  let(:steam_id) { "76561198000000001" }

  context "when UserInventorySyncService succeeds" do
    let(:item) { create(:item) }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [ { classid: "1", market_hash_name: item.market_hash_name } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "syncs the user's inventory" do
      perform

      expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(item)
    end
  end

  context "when UserInventorySyncService fails" do
    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "logs a warning and does not raise" do
      expect(Rails.logger).to receive(:warn).with(/\[UserInventorySyncWorker\] Failed for #{steam_id}/)

      expect { perform }.not_to raise_error
    end
  end
end
