require "rails_helper"

RSpec.describe InventoryValuation do
  let(:steam_id) { "76561198000000001" }

  describe ".current" do
    it "returns zero counts for an empty inventory" do
      inventory = create(:user_inventory, steam_id: steam_id)

      snapshot = described_class.current(inventory)

      aggregate_failures do
        expect(snapshot.total_value_cents).to eq(0)
        expect(snapshot.items_count).to eq(0)
        expect(snapshot.pricable_items_count).to eq(0)
        expect(snapshot.priced_items_count).to eq(0)
        expect(snapshot.complete?).to be(true)
        expect(snapshot.oldest_price_at).to be_nil
      end
    end

    it "sums priced items and is complete when every pricable item is priced" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 1000),
        create(:item, current_price_cents: 500)
      ])

      snapshot = described_class.current(inventory)

      aggregate_failures do
        expect(snapshot.total_value_cents).to eq(1500)
        expect(snapshot.items_count).to eq(2)
        expect(snapshot.pricable_items_count).to eq(2)
        expect(snapshot.priced_items_count).to eq(2)
        expect(snapshot.complete?).to be(true)
      end
    end

    it "is partial when a marketable item has never had a price" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 1000),
        create(:item, :without_price)
      ])

      snapshot = described_class.current(inventory)

      aggregate_failures do
        expect(snapshot.total_value_cents).to eq(1000)
        expect(snapshot.items_count).to eq(2)
        expect(snapshot.pricable_items_count).to eq(2)
        expect(snapshot.priced_items_count).to eq(1)
        expect(snapshot.complete?).to be(false)
      end
    end

    it "does not let unpriced non-marketable or price-unavailable items block completeness" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 1000),
        create(:item, :without_price, :non_marketable),
        create(:item, :without_price, :price_unavailable)
      ])

      snapshot = described_class.current(inventory)

      aggregate_failures do
        expect(snapshot.total_value_cents).to eq(1000)
        expect(snapshot.items_count).to eq(3)
        expect(snapshot.pricable_items_count).to eq(1)
        expect(snapshot.priced_items_count).to eq(1)
        expect(snapshot.complete?).to be(true)
      end
    end

    it "includes the last known price of an unavailable item without letting it affect completeness" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 1000),
        create(:item, :price_unavailable, current_price_cents: 500)
      ])

      snapshot = described_class.current(inventory)

      aggregate_failures do
        expect(snapshot.total_value_cents).to eq(1500)
        expect(snapshot.pricable_items_count).to eq(1)
        expect(snapshot.priced_items_count).to eq(1)
        expect(snapshot.complete?).to be(true)
      end
    end

    it "reports the oldest price timestamp among priced pricable items" do
      older = create(:item, current_price_cents: 1000, price_updated_at: 3.days.ago)
      newer = create(:item, current_price_cents: 500, price_updated_at: 1.hour.ago)
      unpriced = create(:item, :without_price)
      inventory = create(:user_inventory, steam_id: steam_id, items: [ older, newer, unpriced ])

      snapshot = described_class.current(inventory)

      expect(snapshot.oldest_price_at).to be_within(1.second).of(older.price_updated_at)
    end
  end

  describe ".series" do
    it "appends a live point and replaces today's stored value" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 200)
      ])
      create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 1000, **complete_counts)
      create(:inventory_value_log, steam_id: steam_id, log_date: Date.current, total_value_cents: 100, **complete_counts)

      series = described_class.series(steam_id, Options::DateRange::Last7Days, current: described_class.current(inventory))

      aggregate_failures do
        expect(series.points.size).to eq(2)
        expect(series.points.first.total_value_cents).to eq(1000)
        expect(series.points.last.total_value_cents).to eq(200)
        expect(series.points.last.at).not_to eq(Date.current.iso8601)
        expect(series.change_cents).to eq(-800)
        expect(series.change_percent).to eq(-80.0)
        expect(series.change_basis_at).to eq(series.points.first.at)
        expect(series.change_available).to be(true)
        expect(series.change_partial).to be(false)
      end
    end

    it "filters stored points to the requested period" do
      inventory = create(:user_inventory, steam_id: steam_id)
      create(:inventory_value_log, steam_id: steam_id, log_date: 10.days.ago.to_date, total_value_cents: 50, **complete_counts)
      create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 100, **complete_counts)

      series = described_class.series(steam_id, Options::DateRange::Last7Days, current: described_class.current(inventory))

      aggregate_failures do
        expect(series.points.map(&:total_value_cents)).to eq([ 100, 0 ])
        expect(series.change_cents).to eq(-100)
      end
    end

    it "marks the change partial when the baseline row is incomplete" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 200)
      ])
      create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 1000, **partial_counts)

      series = described_class.series(steam_id, Options::DateRange::Last7Days, current: described_class.current(inventory))

      expect(series.change_partial).to be(true)
    end

    it "makes the change unavailable when there is only the live point" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 200)
      ])

      series = described_class.series(steam_id, Options::DateRange::Last7Days, current: described_class.current(inventory))

      aggregate_failures do
        expect(series.points.size).to eq(1)
        expect(series.change_cents).to eq(0)
        expect(series.change_available).to be(false)
        expect(series.change_basis_at).to be_nil
      end
    end
  end

  describe ".baseline_for" do
    it "returns the latest row on or before the date for each steam_id" do
      old = create(:inventory_value_log, steam_id: steam_id, log_date: 3.days.ago.to_date, total_value_cents: 100)
      latest = create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 200)
      create(:inventory_value_log, steam_id: steam_id, log_date: Date.current, total_value_cents: 300)

      baselines = described_class.baseline_for([ steam_id ], Date.current - 1)

      expect(baselines[steam_id]).to eq(latest)
      expect(baselines[steam_id]).not_to eq(old)
    end

    it "omits steam_ids without a baseline" do
      baselines = described_class.baseline_for([ steam_id ], Date.current - 1)

      expect(baselines).to eq({})
    end
  end

  describe ".page" do
    it "returns a nil current and empty series for an unknown steam_id" do
      page = described_class.page("unknown", Options::DateRange::Last7Days)

      aggregate_failures do
        expect(page.current).to be_nil
        expect(page.series.points).to eq([])
        expect(page.series.change_available).to be(false)
      end
    end

    it "returns the current snapshot and series for an existing inventory" do
      create(:user_inventory, steam_id: steam_id, items: [ create(:item, current_price_cents: 200) ])

      page = described_class.page(steam_id, Options::DateRange::Last7Days)

      aggregate_failures do
        expect(page.current).not_to be_nil
        expect(page.current.total_value_cents).to eq(200)
        expect(page.series.points.last.total_value_cents).to eq(200)
      end
    end
  end

  def complete_counts
    { items_count: 1, pricable_items_count: 1, priced_items_count: 1 }
  end

  def partial_counts
    { items_count: 2, pricable_items_count: 2, priced_items_count: 1 }
  end
end
