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

  describe "#since / #since_date" do
    around { |example| travel_to(Time.zone.local(2026, 10, 19, 12, 0, 0)) { example.run } }

    it "converts each duration into a cutoff time and date" do
      aggregate_failures do
        expect(PricePeriod::TwentyFourHours.since).to eq(1.day.ago)
        expect(PricePeriod::TwentyFourHours.since_date).to eq(1.day.ago.to_date)
        expect(PricePeriod::SevenDays.since).to eq(7.days.ago)
        expect(PricePeriod::ThirtyDays.since_date).to eq(30.days.ago.to_date)
        expect(PricePeriod::OneYear.since_date).to eq(365.days.ago.to_date)
      end
    end

    it "returns nil for all (no cutoff)" do
      aggregate_failures do
        expect(PricePeriod::All.since).to be_nil
        expect(PricePeriod::All.since_date).to be_nil
      end
    end
  end

  describe ".resolve" do
    let(:supported) { [ PricePeriod::SevenDays, PricePeriod::ThirtyDays, PricePeriod::All ] }

    it "returns the default when the raw value is blank" do
      aggregate_failures do
        expect(described_class.resolve(nil, supported: supported, default: PricePeriod::SevenDays))
          .to eq(PricePeriod::SevenDays)
        expect(described_class.resolve("", supported: supported, default: PricePeriod::SevenDays))
          .to eq(PricePeriod::SevenDays)
      end
    end

    it "returns a supported period for a recognized value" do
      expect(described_class.resolve("30d", supported: supported, default: PricePeriod::SevenDays))
        .to eq(PricePeriod::ThirtyDays)
    end

    it "returns nil for an unknown value" do
      expect(described_class.resolve("3weeks", supported: supported, default: PricePeriod::SevenDays)).to be_nil
    end

    it "returns nil for a known but unsupported value" do
      expect(described_class.resolve("24h", supported: supported, default: PricePeriod::SevenDays)).to be_nil
    end
  end
end
