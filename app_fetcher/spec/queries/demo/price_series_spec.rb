require "rails_helper"

RSpec.describe Demo::PriceSeries do
  subject(:series) do
    described_class.new(
      market_hash_name: "AK-47 | Redline (Field-Tested)",
      current_price_cents: 4_200
    )
  end

  it "is deterministic for the same name and anchor" do
    first = described_class.new(market_hash_name: series_name, current_price_cents: 4_200)
    second = described_class.new(market_hash_name: series_name, current_price_cents: 4_200)

    attributes = ->(points) { points.map { |point| [ point.at, point.price_cents, point.volume ] } }

    expect(attributes.call(first.daily)).to eq(attributes.call(second.daily))
  end

  it "ends the daily series at the anchor" do
    expect(series.daily.last.price_cents).to eq(4_200)
  end

  it "ends the hourly series at the anchor" do
    expect(series.hourly.last.price_cents).to eq(4_200)
  end

  it "returns the expected number of points per window" do
    aggregate_failures do
      expect(series.points_for(Options::DateRange::Last24Hours).size).to eq(24)
      expect(series.points_for(Options::DateRange::Last7Days).size).to eq(7)
      expect(series.points_for(Options::DateRange::Last30Days).size).to eq(30)
      expect(series.points_for(Options::DateRange::LastYear).size).to eq(365)
      expect(series.points_for(Options::DateRange::AllTime).size).to eq(365)
    end
  end

  it "returns a five-point trend ending at the anchor" do
    trend = series.trend

    aggregate_failures do
      expect(trend.size).to eq(5)
      expect(trend.last[:price_cents]).to eq(4_200)
      expect(trend.map { |point| point[:volume] }).to all(be_positive)
    end
  end

  it "derives the 24h change from the last two daily points" do
    points = series.points_for(Options::DateRange::Last7Days)

    expect(series.change_24h_cents).to eq(points.last.price_cents - points[-2].price_cents)
  end

  it "keeps every generated price on a whole-dollar boundary" do
    prices = series.daily.map(&:price_cents) + series.hourly.map(&:price_cents)

    expect(prices).to all(satisfy { |price_cents| price_cents.positive? && (price_cents % 100).zero? })
  end

  it "rounds a low anchor up to the minimum whole-dollar price" do
    low = described_class.new(market_hash_name: "P250 | Sand Dune (Factory New)", current_price_cents: 1)

    expect(low.daily.map(&:price_cents)).to all(be >= 100)
  end

  it "varies by item name for the same anchor" do
    other = described_class.new(
      market_hash_name: "AWP | Asiimov (Field-Tested)",
      current_price_cents: 4_200
    )

    expect(other.daily).not_to eq(series.daily)
  end

  def series_name
    "AK-47 | Redline (Field-Tested)"
  end
end
