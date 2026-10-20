require "rails_helper"

RSpec.describe RarityBreakdownQuery do
  describe ".call" do
    it "groups counts per inventory without bleeding between inventories" do
      covert_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: covert_inventory, item: create(:item, metadata: { rarity: "Covert" }))
      create(:user_inventory_item, user_inventory: covert_inventory, item: create(:item, metadata: { rarity: "Covert" }))
      classified_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: classified_inventory, item: create(:item, metadata: { rarity: "Classified" }))

      counts = described_class.call([ covert_inventory.id, classified_inventory.id ])

      expect(counts).to eq(
        covert_inventory.id => { RarityTier::Covert => 2 },
        classified_inventory.id => { RarityTier::Classified => 1 }
      )
    end

    it "maps star-prefixed and Contraband items to Gold and omits Extraordinary collectibles and unknown rarities" do
      inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, market_hash_name: "★ Karambit | Doppler", metadata: { rarity: "Covert" }))
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, market_hash_name: "2020 Service Medal", metadata: { rarity: "Extraordinary", category: "Collectible" }))
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, metadata: { rarity: "Contraband" }))
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, metadata: { rarity: "Unknown" }))

      counts = described_class.call([ inventory.id ])

      expect(counts[inventory.id]).to eq(RarityTier::Gold => 2)
    end

    it "returns an empty hash for empty ids" do
      expect(described_class.call([])).to eq({})
    end
  end
end
