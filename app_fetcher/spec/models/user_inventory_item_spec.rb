require "rails_helper"

RSpec.describe UserInventoryItem do
  it "belongs to a user_inventory and an item" do
    user_inventory_item = create(:user_inventory_item)

    aggregate_failures do
      expect(user_inventory_item.user_inventory).to be_a(UserInventory)
      expect(user_inventory_item.item).to be_a(Item)
    end
  end
end
