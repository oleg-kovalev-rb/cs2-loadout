require "rails_helper"

RSpec.describe InventoryValueQuery do
  let(:steam_id) { "76561198000000001" }

  describe ".current" do
    it "returns zero counts for an empty inventory" do
      inventory = create(:user_inventory, steam_id: steam_id)

      snapshot = described_class.snapshot_for(inventory)

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

      snapshot = described_class.snapshot_for(inventory)

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

      snapshot = described_class.snapshot_for(inventory)

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

      snapshot = described_class.snapshot_for(inventory)

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

      snapshot = described_class.snapshot_for(inventory)

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

      snapshot = described_class.snapshot_for(inventory)

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

      series = described_class.history(steam_id, Options::DateRange::Last7Days, current: described_class.snapshot_for(inventory))

      aggregate_failures do
        expect(series.points.size).to eq(2)
        expect(series.points.first.total_value_cents).to eq(1000)
        expect(series.points.last.total_value_cents).to eq(200)
        expect(series.points.last.at).to be_a(Time)
        expect(series.points.last.at).to be > series.points.first.at
        expect(series.delta.cents).to eq(-800)
        expect(series.delta.percent).to eq(-80.0)
        expect(series.delta.basis_at).to eq(series.points.first.at)
        expect(series.delta.available).to be(true)
        expect(series.delta.partial).to be(false)
      end
    end

    it "filters stored points to the requested period" do
      inventory = create(:user_inventory, steam_id: steam_id)
      create(:inventory_value_log, steam_id: steam_id, log_date: 10.days.ago.to_date, total_value_cents: 50, **complete_counts)
      create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 100, **complete_counts)

      series = described_class.history(steam_id, Options::DateRange::Last7Days, current: described_class.snapshot_for(inventory))

      aggregate_failures do
        expect(series.points.map(&:total_value_cents)).to eq([ 100, 0 ])
        expect(series.delta.cents).to eq(-100)
      end
    end

    it "marks the change partial when the baseline row is incomplete" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 200)
      ])
      create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 1000, **partial_counts)

      series = described_class.history(steam_id, Options::DateRange::Last7Days, current: described_class.snapshot_for(inventory))

      expect(series.delta.partial).to be(true)
    end

    it "makes the change unavailable when there is only the live point" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 200)
      ])

      series = described_class.history(steam_id, Options::DateRange::Last7Days, current: described_class.snapshot_for(inventory))

      aggregate_failures do
        expect(series.points.size).to eq(1)
        expect(series.delta.cents).to eq(0)
        expect(series.delta.available).to be(false)
        expect(series.delta.basis_at).to be_nil
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

  describe ".call" do
    it "returns a nil snapshot and empty history for an unknown steam_id" do
      page = described_class.call("unknown", Options::DateRange::Last7Days)

      aggregate_failures do
        expect(page.snapshot).to be_nil
        expect(page.history.points).to eq([])
        expect(page.history.delta.available).to be(false)
      end
    end

    it "returns the snapshot and history for an existing inventory" do
      create(:user_inventory, steam_id: steam_id, items: [ create(:item, current_price_cents: 200) ])

      page = described_class.call(steam_id, Options::DateRange::Last7Days)

      aggregate_failures do
        expect(page.snapshot).not_to be_nil
        expect(page.snapshot.total_value_cents).to eq(200)
        expect(page.history.points.last.total_value_cents).to eq(200)
      end
    end
  end

  describe ".with_aggregates / .snapshot_from" do
    it "keeps the aliases used by inventory sorting and reads a typed snapshot" do
      inventory = create(:user_inventory, steam_id: steam_id, items: [
        create(:item, current_price_cents: 1000),
        create(:item, current_price_cents: 500)
      ])

      scope = described_class.with_aggregates(
        UserInventory
          .left_joins(user_inventory_items: :item)
          .group("user_inventories.id")
          .select("user_inventories.id", "user_inventories.steam_id", "user_inventories.updated_at")
      )
      record = T.must(scope.to_a.find { |row| row.id == inventory.id })
      snapshot = described_class.snapshot_from(record)

      aggregate_failures do
        expect(record.read_attribute(:total_value_cents)).to eq(1500)
        expect(snapshot.total_value_cents).to eq(1500)
        expect(snapshot.items_count).to eq(2)
        expect(snapshot.complete?).to be(true)
      end
    end
  end

  describe ".delta_for" do
    let(:snapshot) do
      InventoryValueQuery::ValueSnapshot.new(
        total_value_cents: 1500,
        items_count: 2,
        pricable_items_count: 2,
        priced_items_count: 2,
        oldest_price_at: nil
      )
    end

    it "returns an unavailable zero delta without a baseline" do
      delta = described_class.delta_for(snapshot, nil)

      aggregate_failures do
        expect(delta.cents).to eq(0)
        expect(delta.percent).to eq(0.0)
        expect(delta.basis_at).to be_nil
        expect(delta.available).to be(false)
      end
    end

    it "returns an unavailable delta for a baseline older than the max age" do
      baseline = create(:inventory_value_log,
        steam_id: steam_id, log_date: 3.days.ago.to_date, total_value_cents: 1000,
        items_count: 2, pricable_items_count: 2, priced_items_count: 2)

      delta = described_class.delta_for(snapshot, baseline)

      aggregate_failures do
        expect(delta.cents).to eq(0)
        expect(delta.available).to be(false)
        expect(delta.basis_at&.to_date).to eq(baseline.log_date)
      end
    end

    it "computes cents/percent and marks a partial delta when the baseline is incomplete" do
      baseline = create(:inventory_value_log,
        steam_id: steam_id, log_date: 1.day.ago.to_date, total_value_cents: 1000,
        items_count: 2, pricable_items_count: 2, priced_items_count: 1)

      delta = described_class.delta_for(snapshot, baseline)

      aggregate_failures do
        expect(delta.cents).to eq(500)
        expect(delta.percent).to eq(50.0)
        expect(delta.partial).to be(true)
        expect(delta.available).to be(true)
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
