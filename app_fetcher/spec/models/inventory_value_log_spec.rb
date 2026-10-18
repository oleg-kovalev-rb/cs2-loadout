require "rails_helper"

RSpec.describe InventoryValueLog do
  describe "#complete?" do
    it "treats a legacy row without counters as complete" do
      log = build(:inventory_value_log, items_count: nil, pricable_items_count: nil, priced_items_count: nil)

      expect(log.complete?).to be(true)
    end

    it "is complete when every pricable item was priced" do
      log = build(:inventory_value_log, items_count: 3, pricable_items_count: 2, priced_items_count: 2)

      expect(log.complete?).to be(true)
    end

    it "is incomplete when a pricable item was not priced" do
      log = build(:inventory_value_log, items_count: 3, pricable_items_count: 2, priced_items_count: 1)

      expect(log.complete?).to be(false)
    end

    it "is complete for an inventory with no pricable items" do
      log = build(:inventory_value_log, items_count: 2, pricable_items_count: 0, priced_items_count: 0)

      expect(log.complete?).to be(true)
    end
  end
end
