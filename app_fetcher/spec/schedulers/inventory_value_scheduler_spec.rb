require "rails_helper"

RSpec.describe InventoryValueScheduler do
  subject(:perform) { described_class.new.perform }

  let(:enqueued_steam_ids) { InventoryValueUpdateWorker.jobs.map { |job| job["args"].first } }

  describe "#perform" do
    context "with a steam_id that already has a log entry" do
      let!(:log) { create(:inventory_value_log, steam_id: "76561198000000001") }

      it "enqueues the worker for that steam_id" do
        perform

        expect(enqueued_steam_ids).to include("76561198000000001")
      end
    end

    context "with a steam_id that has multiple historical log entries" do
      let!(:logs) do
        (1..3).map { |n| create(:inventory_value_log, steam_id: "76561198000000002", log_date: n.days.ago.to_date) }
      end

      it "enqueues the worker exactly once for that steam_id" do
        perform

        expect(enqueued_steam_ids.count("76561198000000002")).to eq(1)
      end
    end

    context "with no log entries at all" do
      it "enqueues nothing" do
        perform

        expect(InventoryValueUpdateWorker.jobs).to be_empty
      end
    end
  end
end
