require "rails_helper"

RSpec.describe UserInventory do
  describe "validations" do
    it "requires a unique steam_id" do
      create(:user_inventory, steam_id: "76561198000000001")
      duplicate = build(:user_inventory, steam_id: "76561198000000001")

      expect(duplicate).not_to be_valid
    end
  end

  describe ".sync!" do
    subject(:sync!) { described_class.sync!(steam_id, item_ids) }

    let(:steam_id) { "76561198000000001" }
    let(:item_ids) { [ item_one.id, item_two.id ] }
    let(:item_one) { create(:item) }
    let(:item_two) { create(:item) }

    context "with no existing UserInventory for this steam_id" do
      it "creates one and links the given items" do
        sync!

        user_inventory = UserInventory.find_by(steam_id: steam_id)

        aggregate_failures do
          expect(user_inventory).to be_present
          expect(user_inventory.items).to contain_exactly(item_one, item_two)
        end
      end
    end

    context "with an existing UserInventory and item set" do
      let!(:user_inventory) { create(:user_inventory, steam_id: steam_id) }
      let!(:stale_link) { create(:user_inventory_item, user_inventory: user_inventory, item: create(:item)) }

      it "fully replaces the prior item set" do
        sync!

        expect(user_inventory.reload.items).to contain_exactly(item_one, item_two)
      end

      it "touches updated_at" do
        previous_updated_at = user_inventory.updated_at

        travel_to(1.day.from_now) { sync! }

        expect(user_inventory.reload.updated_at).to be > previous_updated_at
      end
    end

    context "with an empty item_ids array" do
      let(:item_ids) { [] }

      it "leaves the UserInventory with zero linked items" do
        sync!

        expect(UserInventory.find_by(steam_id: steam_id).items).to be_empty
      end
    end

    context "called twice in a row" do
      it "is idempotent, ending with the second call's item set" do
        sync!
        described_class.sync!(steam_id, [ item_one.id ])

        expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(item_one)
      end
    end
  end
end
