require "rails_helper"

RSpec.describe PriceScheduler do
  subject(:perform) { described_class.new.perform }

  let(:enqueued_ids) { PriceUpdateWorker.jobs.map { |job| job["args"].first } }

  describe "#perform" do
    context "with a stale item and an item with no price yet" do
      let!(:stale_item) { create(:item, :stale) }
      let!(:unpriced_item) { create(:item, :without_price) }

      it "enqueues PriceUpdateWorker for both" do
        perform

        expect(enqueued_ids).to include(stale_item.id)
        expect(enqueued_ids).to include(unpriced_item.id)
      end
    end

    context "with an item updated recently that already has a price" do
      let!(:fresh_item) { create(:item) }

      it "does not enqueue it" do
        perform

        expect(enqueued_ids).not_to include(fresh_item.id)
      end
    end

    context "with several qualifying items" do
      let!(:items) { create_list(:item, 3, :stale) }

      it "enqueues one job per item" do
        perform

        expect(enqueued_ids.count { |id| items.map(&:id).include?(id) }).to eq(3)
      end
    end
  end
end
