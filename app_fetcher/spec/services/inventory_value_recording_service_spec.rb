require "rails_helper"

RSpec.describe InventoryValueRecordingService do
  subject(:record) { described_class.call(steam_id) }

  let(:steam_id) { "76561198000000001" }

  context "with a fully priced inventory" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:other_priced_item) { create(:item, current_price_cents: 1200) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item, other_priced_item ]) }

    it "writes and returns today's log entry with the summed total" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(record.data).to eq(log)
        expect(log.total_value_cents).to eq(5045)
      end
    end
  end

  context "with an unpriced marketable item in the inventory" do
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ unpriced_item ]) }

    it "skips writing anything, since the inventory is not fully priced" do
      record

      aggregate_failures do
        expect(record.skipped?).to be(true)
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current)).not_to exist
      end
    end
  end

  context "with an unpriced but price-unavailable marketable item" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unavailable_item) { create(:item, :without_price, :price_unavailable) }
    let!(:user_inventory) do
      create(:user_inventory, steam_id: steam_id, items: [ priced_item, unavailable_item ])
    end

    it "writes the log, not blocking on the price-unavailable item" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(3845)
      end
    end
  end

  context "with an unpriced non-marketable item (which never gets a price)" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unpriced_non_marketable) { create(:item, :without_price, :non_marketable) }
    let!(:user_inventory) do
      create(:user_inventory, steam_id: steam_id, items: [ priced_item, unpriced_non_marketable ])
    end

    it "still writes the log, summing only the priced items" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(3845)
      end
    end
  end

  context "with no UserInventory row at all for this steam_id" do
    it "skips writing anything, without error" do
      record

      aggregate_failures do
        expect(record.skipped?).to be(true)
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current)).not_to exist
      end
    end
  end

  context "when a log entry for this steam_id/day already exists" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item ]) }

    before { create(:inventory_value_log, steam_id: steam_id, log_date: Date.current, total_value_cents: 1) }

    it "updates the existing row in place instead of creating a second one" do
      record

      aggregate_failures do
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current).count).to eq(1)
        expect(InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current).total_value_cents).to eq(3845)
      end
    end
  end
end
