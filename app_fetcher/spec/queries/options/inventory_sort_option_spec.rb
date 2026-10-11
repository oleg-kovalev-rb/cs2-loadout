require "rails_helper"

RSpec.describe Options::InventorySortOption do
  describe "#apply" do
    it "ValueDesc orders by aggregated total_value_cents descending" do
      low = create(:user_inventory)
      create(:user_inventory_item, user_inventory: low, item: create(:item, current_price_cents: 100))
      high = create(:user_inventory)
      create(:user_inventory_item, user_inventory: high, item: create(:item, current_price_cents: 900))

      ordered = described_class::ValueDesc.apply(aggregated_scope.where(id: [ low.id, high.id ])).map(&:steam_id)

      expect(ordered).to eq([ high.steam_id, low.steam_id ])
    end

    it "ItemsDesc orders by aggregated items_count descending" do
      few = create(:user_inventory)
      create(:user_inventory_item, user_inventory: few, item: create(:item))
      many = create(:user_inventory)
      create_list(:item, 3).each { |item| create(:user_inventory_item, user_inventory: many, item: item) }

      ordered = described_class::ItemsDesc.apply(aggregated_scope.where(id: [ few.id, many.id ])).map(&:steam_id)

      expect(ordered).to eq([ many.steam_id, few.steam_id ])
    end

    it "RecentlySynced orders by updated_at descending" do
      older = create(:user_inventory, updated_at: 2.days.ago)
      newer = create(:user_inventory, updated_at: 1.hour.ago)

      ordered = described_class::RecentlySynced.apply(aggregated_scope.where(id: [ older.id, newer.id ])).map(&:steam_id)

      expect(ordered).to eq([ newer.steam_id, older.steam_id ])
    end

    it "ChangeDesc orders by aggregated change_24h_cents descending" do
      losing = create(:user_inventory)
      create(:user_inventory_item, user_inventory: losing, item: create(:item, change_24h_cents: -50))
      gaining = create(:user_inventory)
      create(:user_inventory_item, user_inventory: gaining, item: create(:item, change_24h_cents: 100))

      ordered = described_class::ChangeDesc.apply(aggregated_scope.where(id: [ losing.id, gaining.id ])).map(&:steam_id)

      expect(ordered).to eq([ gaining.steam_id, losing.steam_id ])
    end
  end

  def aggregated_scope
    UserInventory
      .left_joins(user_inventory_items: :item)
      .group("user_inventories.id")
      .select(
        "user_inventories.*",
        "COUNT(items.id) AS items_count",
        "COALESCE(SUM(items.current_price_cents), 0) AS total_value_cents",
        "COALESCE(SUM(items.change_24h_cents), 0) AS change_24h_cents"
      )
  end
end
