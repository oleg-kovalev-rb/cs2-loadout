require "rails_helper"

RSpec.describe Item do
  describe ".marketable" do
    subject(:marketable_items) { described_class.marketable }

    let!(:marketable_item) { create(:item, metadata: { marketable: true }) }
    let!(:non_marketable_item) { create(:item, metadata: { marketable: false }) }
    let!(:unknown_marketability_item) { create(:item, metadata: {}) }

    it "includes only items explicitly marked marketable" do
      expect(marketable_items).to include(marketable_item)
      expect(marketable_items).not_to include(non_marketable_item)
      expect(marketable_items).not_to include(unknown_marketability_item)
    end
  end

  describe ".stale_or_unpriced" do
    subject(:items_needing_price) { described_class.stale_or_unpriced }

    let!(:stale_item) { create(:item, :stale) }
    let!(:unpriced_item) { create(:item, :without_price) }
    let!(:fresh_priced_item) { create(:item) }

    it "includes stale or unpriced items but not a fresh, priced item" do
      expect(items_needing_price).to include(stale_item)
      expect(items_needing_price).to include(unpriced_item)
      expect(items_needing_price).not_to include(fresh_priced_item)
    end
  end

  describe ".due_for_price_update" do
    subject(:due_items) { described_class.due_for_price_update }

    let!(:marketable_stale_item) { create(:item, :stale, metadata: { marketable: true }) }
    let!(:non_marketable_stale_item) { create(:item, :stale, metadata: { marketable: false }) }
    let!(:marketable_fresh_priced_item) { create(:item, metadata: { marketable: true }) }

    it "includes only marketable items that are stale or unpriced" do
      expect(due_items).to include(marketable_stale_item)
      expect(due_items).not_to include(non_marketable_stale_item)
      expect(due_items).not_to include(marketable_fresh_priced_item)
    end
  end
end
