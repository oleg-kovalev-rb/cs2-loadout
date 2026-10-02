require "rails_helper"

RSpec.describe UserInventoryCache do
  let(:steam_id) { "76561198000000001" }

  describe ".fetch" do
    context "when no UserInventory exists for this steam_id" do
      it "returns nil and does not write to the cache" do
        expect(described_class.fetch(steam_id)).to be_nil
        expect(Rails.cache.exist?([ "user_inventory", 2, steam_id ])).to be(false)
      end
    end

    context "when a UserInventory exists with items" do
      let(:item) { create(:item) }
      let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ item ]) }

      it "returns the user's items and writes them to the cache" do
        expect(described_class.fetch(steam_id)).to contain_exactly(item)
        expect(Rails.cache.exist?([ "user_inventory", 2, steam_id ])).to be(true)
      end

      it "does not hit the database on a second fetch" do
        described_class.fetch(steam_id)

        queries = count_queries(model: UserInventory) { described_class.fetch(steam_id) }

        expect(queries).to eq(0)
      end
    end
  end

  describe ".invalidate" do
    it "clears a previously cached entry" do
      item = create(:item)
      create(:user_inventory, steam_id: steam_id, items: [ item ])
      described_class.fetch(steam_id)

      described_class.invalidate(steam_id)

      expect(Rails.cache.exist?([ "user_inventory", 2, steam_id ])).to be(false)
    end

    it "is a no-op when nothing is cached for this steam_id" do
      expect { described_class.invalidate(steam_id) }.not_to raise_error
    end
  end
end
