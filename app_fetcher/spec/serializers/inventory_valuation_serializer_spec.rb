require "rails_helper"

RSpec.describe InventoryValuationSerializer do
  describe ".call" do
    let(:point) do
      InventoryValuation::Point.new(
        at: "2024-01-01T00:00:00Z",
        total_value_cents: 1000,
        complete: true,
        priced_items_count: 1,
        pricable_items_count: 1
      )
    end
    let(:snapshot) do
      InventoryValuation::Snapshot.new(
        total_value_cents: 1500,
        items_count: 1,
        pricable_items_count: 1,
        priced_items_count: 1,
        oldest_price_at: Time.utc(2024, 1, 2, 12, 0, 0)
      )
    end
    let(:series) do
      InventoryValuation::Series.new(
        points: [ point ],
        change_cents: 500,
        change_percent: 50.0,
        change_basis_at: "2024-01-01T00:00:00Z",
        change_partial: false,
        change_available: true
      )
    end

    it "returns the contracted current/history/change shape" do
      page = InventoryValuation::Page.new(current: snapshot, series: series)

      result = described_class.call(page)

      expect(result).to eq(
        current: {
          total_value_cents: 1500,
          items_count: 1,
          pricable_items_count: 1,
          priced_items_count: 1,
          complete: true,
          oldest_price_at: "2024-01-02T12:00:00Z"
        },
        history: [
          {
            at: "2024-01-01T00:00:00Z",
            total_value_cents: 1000,
            complete: true,
            priced_items_count: 1,
            pricable_items_count: 1
          }
        ],
        change: {
          cents: 500,
          percent: 50.0,
          basis_at: "2024-01-01T00:00:00Z",
          partial: false,
          available: true
        }
      )
    end

    it "renders a nil current and an empty history when there is no inventory" do
      page = InventoryValuation::Page.new(
        current: nil,
        series: InventoryValuation::Series.new(
          points: [],
          change_cents: 0,
          change_percent: 0.0,
          change_basis_at: nil,
          change_partial: false,
          change_available: false
        )
      )

      result = described_class.call(page)

      aggregate_failures do
        expect(result[:current]).to be_nil
        expect(result[:history]).to eq([])
        expect(result[:change]).to eq(
          cents: 0, percent: 0.0, basis_at: nil, partial: false, available: false
        )
      end
    end

    it "keeps oldest_price_at nil when the snapshot has no known price date" do
      snapshot = InventoryValuation::Snapshot.new(
        total_value_cents: 0,
        items_count: 0,
        pricable_items_count: 0,
        priced_items_count: 0,
        oldest_price_at: nil
      )

      result = described_class.call(InventoryValuation::Page.new(current: snapshot, series: series))

      expect(result[:current][:oldest_price_at]).to be_nil
    end
  end
end
