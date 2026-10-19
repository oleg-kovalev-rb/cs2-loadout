require "rails_helper"

RSpec.describe ItemPriceHistoryQuery do
  let(:item) { create(:item) }

  before do
    create(:price_log, item: item, lowest_price_cents: 1800, volume: 2, created_at: 2.hours.ago)
    create(:price_log, item: item, lowest_price_cents: 2000, volume: 3, created_at: 5.days.ago)
    create(:price_log, item: item, lowest_price_cents: 1500, volume: 1, created_at: 45.days.ago)
    create(:price_log, item: item, lowest_price_cents: 1000, volume: 1, created_at: 400.days.ago)
  end

  it "defaults to the last 30 days and orders points oldest first" do
    page = described_class.call(item, ActionController::Parameters.new)

    aggregate_failures do
      expect(page.range).to eq(Options::DateRange::Last30Days)
      expect(page.points.map(&:price_cents)).to eq([ 2000, 1800 ])
      expect(page.points.first.at).to eq(5.days.ago.iso8601)
      expect(page.points.first.volume).to eq(3)
    end
  end

  it "applies the 24h cutoff" do
    page = described_class.call(item, ActionController::Parameters.new(period: "24h"))

    expect(page.points.map(&:price_cents)).to eq([ 1800 ])
  end

  it "applies the 1y cutoff" do
    page = described_class.call(item, ActionController::Parameters.new(period: "1y"))

    expect(page.points.map(&:price_cents)).to eq([ 1500, 2000, 1800 ])
  end

  it "applies no cutoff for all" do
    page = described_class.call(item, ActionController::Parameters.new(period: "all"))

    expect(page.points.map(&:price_cents)).to eq([ 1000, 1500, 2000, 1800 ])
  end

  it "raises the V1 error for an unrecognized period" do
    expect { described_class.call(item, ActionController::Parameters.new(period: "3weeks")) }
      .to raise_error(Api::V1::UnsupportedParamError, "Unsupported period: 3weeks")
  end
end
