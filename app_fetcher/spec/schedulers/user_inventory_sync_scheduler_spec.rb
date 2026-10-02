require "rails_helper"

RSpec.describe UserInventorySyncScheduler do
  subject(:perform) { described_class.new.perform }

  let(:enqueued_steam_ids) { UserInventorySyncWorker.jobs.map { |job| job["args"].first } }

  describe "#perform" do
    context "with a UserInventory stale beyond the threshold" do
      let!(:stale) { create(:user_inventory, steam_id: "76561198000000001", updated_at: 8.days.ago) }

      it "enqueues the worker for that steam_id" do
        perform

        expect(enqueued_steam_ids).to include("76561198000000001")
      end
    end

    context "with a UserInventory updated within the threshold" do
      let!(:fresh) { create(:user_inventory, steam_id: "76561198000000002", updated_at: 1.day.ago) }

      it "does not enqueue the worker" do
        perform

        expect(enqueued_steam_ids).not_to include("76561198000000002")
      end
    end

    context "with no UserInventory rows at all" do
      it "enqueues nothing" do
        perform

        expect(UserInventorySyncWorker.jobs).to be_empty
      end
    end
  end
end
