require "rails_helper"

RSpec.describe ItemPriceHistorySerializer do
  it "returns a bare point array with formatted timestamps" do
    history = ItemPriceHistoryQuery::ItemPriceHistory.new(
      range: Options::DateRange::Last30Days,
      points: [
        ItemPriceHistoryQuery::PricePoint.new(
          at: Time.utc(2024, 1, 1, 12, 0, 0),
          price_cents: 2000,
          volume: 3
        )
      ]
    )

    expect(described_class.call(history)).to eq(
      [ { at: "2024-01-01T12:00:00Z", price_cents: 2000, volume: 3 } ]
    )
  end

  it "returns an empty array for an empty history" do
    history = ItemPriceHistoryQuery::ItemPriceHistory.new(
      range: Options::DateRange::Last30Days,
      points: []
    )

    expect(described_class.call(history)).to eq([])
  end
end
