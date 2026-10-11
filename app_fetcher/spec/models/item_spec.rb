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

  describe ".by_categories" do
    let!(:rifle) { create(:item, metadata: { category: "Rifles" }) }
    let!(:knife) { create(:item, metadata: { category: "Knives" }) }
    let!(:uncategorized) { create(:item, metadata: {}) }

    it "includes only items matching one of the given categories" do
      result = described_class.by_categories([ "Rifles" ])

      expect(result).to include(rifle)
      expect(result).not_to include(knife)
      expect(result).not_to include(uncategorized)
    end

    it "ORs across multiple given categories" do
      result = described_class.by_categories([ "Rifles", "Knives" ])

      expect(result).to include(rifle, knife)
      expect(result).not_to include(uncategorized)
    end

    it "is a no-op (returns everything) when given a blank list" do
      expect(described_class.by_categories([])).to include(rifle, knife, uncategorized)
      expect(described_class.by_categories(nil)).to include(rifle, knife, uncategorized)
    end

    it "matches nothing for an unrecognized category, without raising" do
      expect(described_class.by_categories([ "NotARealCategory" ])).to be_empty
    end
  end

  describe ".by_rarities" do
    let!(:classified) { create(:item, metadata: { rarity: "Classified" }) }
    let!(:covert) { create(:item, metadata: { rarity: "Covert" }) }
    let!(:unrated) { create(:item, metadata: {}) }

    it "includes only items matching one of the given rarities" do
      result = described_class.by_rarities([ "Classified" ])

      expect(result).to include(classified)
      expect(result).not_to include(covert)
      expect(result).not_to include(unrated)
    end

    it "is a no-op (returns everything) when given a blank list" do
      expect(described_class.by_rarities([])).to include(classified, covert, unrated)
    end
  end

  describe ".stattrak_only" do
    let!(:stattrak_item) { create(:item, metadata: { stattrak: true }) }
    let!(:non_stattrak_item) { create(:item, metadata: { stattrak: false }) }
    let!(:unmarked_item) { create(:item, metadata: {}) }

    it "includes only items explicitly marked stattrak" do
      result = described_class.stattrak_only

      expect(result).to include(stattrak_item)
      expect(result).not_to include(non_stattrak_item)
      expect(result).not_to include(unmarked_item)
    end
  end

  describe ".matching_search" do
    let!(:redline) { create(:item, metadata: { item_name: "Redline" }) }
    let!(:asiimov) { create(:item, metadata: { item_name: "Asiimov" }) }

    it "matches a case-insensitive substring of item_name" do
      expect(described_class.matching_search("red")).to contain_exactly(redline)
    end

    it "is a no-op (returns everything) when given a blank term" do
      expect(described_class.matching_search(nil)).to include(redline, asiimov)
      expect(described_class.matching_search("")).to include(redline, asiimov)
    end

    it "matches nothing for a substring present in no item_name, without raising" do
      expect(described_class.matching_search("zzz_no_match")).to be_empty
    end
  end

  describe ".sorted_by" do
    let!(:cheap) { create(:item, current_price_cents: 100, change_24h_cents: -50, metadata: { item_name: "Bravo" }) }
    let!(:expensive) { create(:item, current_price_cents: 900, change_24h_cents: 200, metadata: { item_name: "Alpha" }) }
    let(:scope) { described_class.where(id: [ cheap.id, expensive.id ]) }

    it "orders by current_price_cents descending for price_desc" do
      expect(scope.sorted_by("price_desc").to_a).to eq([ expensive, cheap ])
    end

    it "orders by current_price_cents ascending for price_asc" do
      expect(scope.sorted_by("price_asc").to_a).to eq([ cheap, expensive ])
    end

    it "orders by metadata item_name ascending for name_asc" do
      expect(scope.sorted_by("name_asc").to_a).to eq([ expensive, cheap ])
    end

    it "orders by change_24h_cents descending for change_24h_desc (and as the default)" do
      expect(scope.sorted_by("change_24h_desc").to_a).to eq([ expensive, cheap ])
    end
  end
end
