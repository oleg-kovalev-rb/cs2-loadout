require "rails_helper"

RSpec.describe Options::DateRange do
  describe "#duration" do
    it "maps 24h to 24 hours" do
      expect(described_class::Last24Hours.duration).to eq(24.hours)
    end

    it "maps 7d to 7 days" do
      expect(described_class::Last7Days.duration).to eq(7.days)
    end

    it "maps 30d to 30 days" do
      expect(described_class::Last30Days.duration).to eq(30.days)
    end

    it "maps 1y to 365 days" do
      expect(described_class::LastYear.duration).to eq(365.days)
    end

    it "maps all to nil (no cutoff)" do
      expect(described_class::AllTime.duration).to be_nil
    end
  end

  describe "#since / #since_date" do
    around { |example| travel_to(Time.zone.local(2026, 10, 19, 12, 0, 0)) { example.run } }

    it "converts each duration into a cutoff time and date" do
      aggregate_failures do
        expect(described_class::Last24Hours.since).to eq(1.day.ago)
        expect(described_class::Last24Hours.since_date).to eq(1.day.ago.to_date)
        expect(described_class::Last7Days.since).to eq(7.days.ago)
        expect(described_class::Last30Days.since_date).to eq(30.days.ago.to_date)
        expect(described_class::LastYear.since_date).to eq(365.days.ago.to_date)
      end
    end

    it "returns nil for all (no cutoff)" do
      aggregate_failures do
        expect(described_class::AllTime.since).to be_nil
        expect(described_class::AllTime.since_date).to be_nil
      end
    end
  end

  describe Options::DateRange::Param do
    let(:allowed_ranges) do
      [ Options::DateRange::Last7Days, Options::DateRange::Last30Days, Options::DateRange::AllTime ]
    end

    let(:param) do
      described_class.new(
        allowed_ranges: allowed_ranges,
        default: Options::DateRange::Last7Days,
        error_class: Api::V1::UnsupportedParamError
      )
    end

    it "returns the default when the raw value is blank" do
      aggregate_failures do
        expect(param.parse(nil)).to eq(Options::DateRange::Last7Days)
        expect(param.parse("")).to eq(Options::DateRange::Last7Days)
      end
    end

    it "returns a supported range for a recognized value" do
      expect(param.parse("30d")).to eq(Options::DateRange::Last30Days)
    end

    it "raises the configured error for an unknown value" do
      expect { param.parse("3weeks") }
        .to raise_error(Api::V1::UnsupportedParamError, "Unsupported period: 3weeks")
    end

    it "raises the configured error for a recognized but disallowed value" do
      expect { param.parse("24h") }
        .to raise_error(Api::V1::UnsupportedParamError, "Unsupported period: 24h")
    end

    it "uses the configured error class" do
      public_param = described_class.new(
        allowed_ranges: allowed_ranges,
        default: Options::DateRange::Last7Days,
        error_class: Api::Public::UnsupportedParamError
      )

      expect { public_param.parse("3weeks") }
        .to raise_error(Api::Public::UnsupportedParamError, "Unsupported period: 3weeks")
    end
  end
end
