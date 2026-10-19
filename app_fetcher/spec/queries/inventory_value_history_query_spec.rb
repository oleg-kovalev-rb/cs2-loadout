require "rails_helper"

RSpec.describe InventoryValueHistoryQuery do
  let(:steam_id) { "76561198000000101" }

  before do
    create(:user_inventory, steam_id: steam_id, items: [ create(:item, current_price_cents: 300) ])
    create(:inventory_value_log, steam_id: steam_id, log_date: 60.days.ago.to_date, total_value_cents: 100)
    create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 200)
  end

  it "defaults to all time" do
    page = described_class.call(steam_id, ActionController::Parameters.new)

    expect(page.series.points.map(&:total_value_cents)).to eq([ 100, 200, 300 ])
  end

  it "applies an explicit supported range" do
    page = described_class.call(steam_id, ActionController::Parameters.new(period: "7d"))

    expect(page.series.points.map(&:total_value_cents)).to eq([ 200, 300 ])
  end

  it "returns a nil current and empty series for an unknown steam_id" do
    page = described_class.call("unknown", ActionController::Parameters.new)

    aggregate_failures do
      expect(page.current).to be_nil
      expect(page.series.points).to eq([])
    end
  end

  it "rejects 24h because inventory value logs are daily" do
    expect { described_class.call(steam_id, ActionController::Parameters.new(period: "24h")) }
      .to raise_error(Api::V1::UnsupportedParamError, "Unsupported period: 24h")
  end

  it "raises the V1 error for an unrecognized period" do
    expect { described_class.call(steam_id, ActionController::Parameters.new(period: "3weeks")) }
      .to raise_error(Api::V1::UnsupportedParamError, "Unsupported period: 3weeks")
  end
end
