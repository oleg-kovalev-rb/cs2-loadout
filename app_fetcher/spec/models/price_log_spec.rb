require "rails_helper"

RSpec.describe PriceLog do
  describe ".for_period" do
    let(:item) { create(:item) }

    it "includes rows on or after the period cutoff and excludes older rows" do
      recent = create(:price_log, item: item, created_at: 2.hours.ago)
      create(:price_log, item: item, created_at: 30.hours.ago)

      result = described_class.where(item_id: item.id).for_period(PricePeriod::TwentyFourHours)

      expect(result).to contain_exactly(recent)
    end

    it "applies no cutoff for all" do
      create(:price_log, item: item, created_at: 2.hours.ago)
      create(:price_log, item: item, created_at: 400.days.ago)

      expect(described_class.where(item_id: item.id).for_period(PricePeriod::All).count).to eq(2)
    end

    it "supports every period" do
      expect(described_class::SUPPORTED_PERIODS).to match_array(PricePeriod.values)
    end
  end
end
