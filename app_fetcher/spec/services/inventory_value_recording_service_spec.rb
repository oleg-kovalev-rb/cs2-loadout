require "rails_helper"

RSpec.describe InventoryValueRecordingService do
  subject(:record) { described_class.call(steam_id) }

  let(:steam_id) { "76561198000000001" }

  context "with a fully priced inventory and no prior log" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:other_priced_item) { create(:item, current_price_cents: 1200) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item, other_priced_item ]) }

    it "writes and returns today's complete log entry with the summed total" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(record.data).to eq(log)
        expect(log.total_value_cents).to eq(5045)
        expect(log.items_count).to eq(2)
        expect(log.pricable_items_count).to eq(2)
        expect(log.priced_items_count).to eq(2)
        expect(log.complete?).to be(true)
      end
    end
  end

  context "bootstrap: a fresh inventory with an unpriced marketable item" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item, unpriced_item ]) }

    it "skips writing until every pricable item has its first price" do
      record

      aggregate_failures do
        expect(record.skipped?).to be(true)
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current)).not_to exist
      end
    end
  end

  context "bootstrap: an old inventory with an unpriced marketable item and at least one price" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) do
      create(:user_inventory, steam_id: steam_id, items: [ priced_item, unpriced_item ], created_at: 3.days.ago)
    end

    it "writes a partial row once the bootstrap timeout has elapsed" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(3845)
        expect(log.items_count).to eq(2)
        expect(log.pricable_items_count).to eq(2)
        expect(log.priced_items_count).to eq(1)
        expect(log.complete?).to be(false)
      end
    end
  end

  context "bootstrap: an old inventory with no priced items at all" do
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) do
      create(:user_inventory, steam_id: steam_id, items: [ unpriced_item ], created_at: 3.days.ago)
    end

    it "skips writing rather than recording a misleading zero" do
      record

      aggregate_failures do
        expect(record.skipped?).to be(true)
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current)).not_to exist
      end
    end
  end

  context "steady state: an existing log and an unpriced marketable item" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item, unpriced_item ]) }

    before { create(:inventory_value_log, steam_id: steam_id, log_date: 1.day.ago.to_date) }

    it "writes a partial row using the prices it has" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(3845)
        expect(log.pricable_items_count).to eq(2)
        expect(log.priced_items_count).to eq(1)
        expect(log.complete?).to be(false)
      end
    end
  end

  context "steady state: an existing log and no priced items" do
    let(:unpriced_item) { create(:item, :without_price) }
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ unpriced_item ]) }

    before { create(:inventory_value_log, steam_id: steam_id, log_date: 1.day.ago.to_date) }

    it "skips the day instead of recording a zero" do
      record

      aggregate_failures do
        expect(record.skipped?).to be(true)
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current)).not_to exist
      end
    end
  end

  context "with an empty inventory" do
    let!(:user_inventory) { create(:user_inventory, steam_id: steam_id) }

    it "writes a complete zero row" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(0)
        expect(log.items_count).to eq(0)
        expect(log.pricable_items_count).to eq(0)
        expect(log.priced_items_count).to eq(0)
        expect(log.complete?).to be(true)
      end
    end
  end

  context "with an unpriced non-marketable item" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unpriced_non_marketable) { create(:item, :without_price, :non_marketable) }
    let!(:user_inventory) do
      create(:user_inventory, steam_id: steam_id, items: [ priced_item, unpriced_non_marketable ])
    end

    it "writes a complete row, summing only the priced items" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(3845)
        expect(log.pricable_items_count).to eq(1)
        expect(log.priced_items_count).to eq(1)
        expect(log.complete?).to be(true)
      end
    end
  end

  context "with an unpriced but price-unavailable item" do
    let(:priced_item) { create(:item, current_price_cents: 3845) }
    let(:unavailable_item) { create(:item, :without_price, :price_unavailable) }
    let!(:user_inventory) do
      create(:user_inventory, steam_id: steam_id, items: [ priced_item, unavailable_item ])
    end

    it "writes the row without treating the unavailable item as pending" do
      record

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(record.success?).to be(true)
        expect(log.total_value_cents).to eq(3845)
        expect(log.pricable_items_count).to eq(1)
        expect(log.priced_items_count).to eq(1)
        expect(log.complete?).to be(true)
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

      log = InventoryValueLog.find_by(steam_id: steam_id, log_date: Date.current)

      aggregate_failures do
        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current).count).to eq(1)
        expect(log.total_value_cents).to eq(3845)
        expect(log.priced_items_count).to eq(1)
        expect(log.complete?).to be(true)
      end
    end
  end
end
