require "test_helper"

class Dashboard::Stub::PortfolioSeriesTest < ActiveSupport::TestCase
  test "each range's series has the right length and ends at the real total" do
    items = [ { current_price_cents: 5000 }, { current_price_cents: 3845 } ]

    result = Dashboard::Stub::PortfolioSeries.call(items)

    assert_equal 8845, result[:current_value_cents]
    assert_equal 24, result[:series]["24h"].size
    assert_equal 7, result[:series]["7d"].size
    assert_equal 30, result[:series]["30d"].size

    result[:series].each_value do |series|
      assert_equal 8845, series.last
    end
  end
end
