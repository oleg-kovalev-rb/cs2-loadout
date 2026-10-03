require "rails_helper"

RSpec.describe PricePeriod do
  describe "#duration" do
    it "maps 24h to 24 hours" do
      expect(PricePeriod::TwentyFourHours.duration).to eq(24.hours)
    end

    it "maps 7d to 7 days" do
      expect(PricePeriod::SevenDays.duration).to eq(7.days)
    end

    it "maps 30d to 30 days" do
      expect(PricePeriod::ThirtyDays.duration).to eq(30.days)
    end

    it "maps 1y to 365 days" do
      expect(PricePeriod::OneYear.duration).to eq(365.days)
    end

    it "maps all to nil (no cutoff)" do
      expect(PricePeriod::All.duration).to be_nil
    end
  end

  describe ".try_deserialize" do
    it "resolves a known serialized value to its enum instance" do
      expect(PricePeriod.try_deserialize("30d")).to eq(PricePeriod::ThirtyDays)
    end

    it "returns nil for an unknown value" do
      expect(PricePeriod.try_deserialize("3weeks")).to be_nil
    end
  end
end
