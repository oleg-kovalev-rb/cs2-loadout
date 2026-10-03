require "rails_helper"

RSpec.describe InventoryValueRecordingService do
  subject(:record) { described_class.call(steam_id) }

  let(:steam_id) { "76561198000000001" }

  context "with priced items in the user's inventory" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:other_priced_item) { create(:item, current_price_cents: 1200) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item, other_priced_item ]) }

    it "writes and returns today's log entry with the summed total" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)
      expect(log.total_value_cents).to eq(5045)
      expect(record.total_value_cents).to eq(5045)
    end
  end

  context "with an item that has no price yet" do
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ unpriced_item ]) }

    it "counts it as 0" do
      record

      expect(InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current).total_value_cents).to eq(0)
    end
  end

  context "with no UserInventory row at all for this steam_id" do
    it "counts it as 0 without error" do
      record

      expect(InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current).total_value_cents).to eq(0)
    end
  end

  context "when a log entry for this steam_id/day already exists" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item ]) }

    before { create(:inventory_value_log, steam_id: steam_id, log_date: Date.current, total_value_cents: 1) }

    it "updates the existing row in place instead of creating a second one" do
      record

      expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current).count).to eq(1)
      expect(InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current).total_value_cents).to eq(3845)
    end
  end
end
