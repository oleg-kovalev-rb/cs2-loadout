require "rails_helper"

RSpec.describe InventoryValueScheduler do
  subject(:perform) { described_class.new.perform }

  let(:enqueued_steam_ids) { InventoryValueUpdateWorker.jobs.map { |job| job["args"].first } }

  describe "#perform" do
    context "with a UserInventory that already has a log entry" do
      let!(:inventory) { create(:user_inventory, steam_id: "76561198000000001") }

      before { create(:inventory_value_log, steam_id: inventory.steam_id) }

      it "enqueues the worker for that steam_id" do
        perform

        expect(enqueued_steam_ids).to include("76561198000000001")
      end
    end

    context "with a UserInventory that has no log entry yet" do
      let!(:inventory) { create(:user_inventory, steam_id: "76561198000000002") }

      it "enqueues the worker for that steam_id" do
        perform

        expect(enqueued_steam_ids).to include("76561198000000002")
      end
    end

    context "with multiple UserInventory rows for distinct steam_ids" do
      let!(:inventories) { create_list(:user_inventory, 2) }

      it "enqueues the worker exactly once per steam_id" do
        perform

        aggregate_failures do
          expect(enqueued_steam_ids).to match_array(inventories.map(&:steam_id))
          expect(enqueued_steam_ids.uniq.size).to eq(enqueued_steam_ids.size)
        end
      end
    end

    context "with no UserInventory rows at all" do
      it "enqueues nothing" do
        perform

        expect(InventoryValueUpdateWorker.jobs).to be_empty
      end
    end
  end
end
