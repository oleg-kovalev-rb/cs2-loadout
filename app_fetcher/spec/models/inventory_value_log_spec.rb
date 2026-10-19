require "rails_helper"

RSpec.describe InventoryValueLog do
  describe ".for_period" do
    let(:steam_id) { "76561198000000999" }

    it "includes rows on or after the period cutoff and excludes older rows" do
      recent = create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date)
      create(:inventory_value_log, steam_id: steam_id, log_date: 10.days.ago.to_date)

      result = described_class.where(steam_id: steam_id).for_period(PricePeriod::SevenDays)

      expect(result).to contain_exactly(recent)
    end

    it "applies no cutoff for all" do
      create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date)
      create(:inventory_value_log, steam_id: steam_id, log_date: 400.days.ago.to_date)

      expect(described_class.where(steam_id: steam_id).for_period(PricePeriod::All).count).to eq(2)
    end

    it "does not support 24h" do
      expect(described_class::SUPPORTED_PERIODS).not_to include(PricePeriod::TwentyFourHours)
    end
  end

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
