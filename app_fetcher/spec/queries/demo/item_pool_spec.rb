require "rails_helper"

RSpec.describe Demo::ItemPool do
  describe ".entries" do
    it "loads the checked-in placeholder pool" do
      entries = described_class.entries

      aggregate_failures do
        expect(entries).not_to be_empty
        expect(entries.first).to include("market_hash_name", "rarity", "category")
      end
    end
  end

  describe ".market_hash_names" do
    it "returns the item names from the pool" do
      names = described_class.market_hash_names

      expect(names).to include("AK-47 | Redline (Field-Tested)")
    end
  end
end
