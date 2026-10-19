require "rails_helper"

RSpec.describe InventoryDetailQuery do
  describe ".call" do
    it "raises ActiveRecord::RecordNotFound for an unknown steam_id" do
      expect { described_class.call("unknown-steam-id", ActionController::Parameters.new) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns valid zero/empty aggregates for a synced inventory with zero items, instead of 404ing" do
      user_inventory = create(:user_inventory)

      page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

      aggregate_failures do
        expect(page.value.snapshot.items_count).to eq(0)
        expect(page.avg_item_value_cents).to eq(0)
        expect(page.priciest_item).to be_nil
        expect(page.rarity_counts).to eq({})
        expect(page.items.entries).to eq([])
        expect(page.value.snapshot.total_value_cents).to eq(0)
      end
    end

    it "excludes items with a nil current_price_cents from priciest_item" do
      user_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, :without_price))
      priced = create(:item, current_price_cents: 500)
      create(:user_inventory_item, user_inventory: user_inventory, item: priced)

      page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

      expect(page.priciest_item).to eq(priced)
    end

    it "computes avg_item_value_cents from total_value_cents and items_count" do
      user_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 1000))
      create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 500))

      page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

      expect(page.avg_item_value_cents).to eq(750)
    end

    it "counts Extraordinary and Contraband rarities under Gold" do
      user_inventory = create(:user_inventory)
      create(
        :user_inventory_item,
        user_inventory: user_inventory,
        item: create(
          :item,
          market_hash_name: "Sport Gloves | Pandora's Box (Minimal Wear)",
          metadata: { rarity: "Extraordinary" }
        )
      )
      create(
        :user_inventory_item,
        user_inventory: user_inventory,
        item: create(
          :item,
          market_hash_name: "M4A4 | Howl (Field-Tested)",
          metadata: { rarity: "Contraband" }
        )
      )

      page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

      expect(page.rarity_counts).to eq(RarityTier::Gold => 2)
    end

    it "scopes rarity counts to only this inventory's items" do
      user_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, metadata: { rarity: "Covert" }))
      create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, metadata: { rarity: "Covert" }))
      other_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: other_inventory, item: create(:item, metadata: { rarity: "Classified" }))

      page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

      expect(page.rarity_counts).to eq(RarityTier::Covert => 2)
    end

    describe "total_value_cents" do
      it "uses the live sum even when a stored log has a different value" do
        user_inventory = create(:user_inventory)
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 1200))
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 800))
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: Date.current, total_value_cents: 5000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.value.snapshot.total_value_cents).to eq(2000)
      end

      it "uses the live sum when no InventoryValueLog rows exist" do
        user_inventory = create(:user_inventory)
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 1200))
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 800))

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.value.snapshot.total_value_cents).to eq(2000)
      end
    end

    describe "completeness" do
      it "is complete when every pricable item has a price" do
        user_inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 1000) ])

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        aggregate_failures do
          expect(page.value.snapshot.complete?).to be(true)
          expect(page.value.snapshot.pricable_items_count).to eq(1)
          expect(page.value.snapshot.priced_items_count).to eq(1)
        end
      end

      it "is partial and reports counts when a marketable item has no price" do
        user_inventory = create(:user_inventory)
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 1000))
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, :without_price))

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        aggregate_failures do
          expect(page.value.snapshot.complete?).to be(false)
          expect(page.value.snapshot.pricable_items_count).to eq(2)
          expect(page.value.snapshot.priced_items_count).to eq(1)
        end
      end

      it "does not let non-marketable or unavailable items block completeness" do
        user_inventory = create(:user_inventory, items: [
          create(:item, current_price_cents: 1000),
          create(:item, :without_price, :non_marketable),
          create(:item, :without_price, :price_unavailable)
        ])

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        aggregate_failures do
          expect(page.value.snapshot.complete?).to be(true)
          expect(page.value.snapshot.pricable_items_count).to eq(1)
          expect(page.value.snapshot.priced_items_count).to eq(1)
        end
      end
    end

    describe "period / history / change_cents / change_percent" do
      it "defaults to 7d and keeps only the live point when the stored rows are outside the window" do
        user_inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 2000) ])
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 10.days.ago.to_date, total_value_cents: 1000)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: Date.current, total_value_cents: 2000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        aggregate_failures do
          expect(page.range).to eq(Options::DateRange::Last7Days)
          expect(page.value.history.points.size).to eq(1)
          expect(page.value.history.points.first.total_value_cents).to eq(2000)
          expect(page.value.history.delta.cents).to eq(0)
          expect(page.value.history.delta.percent).to eq(0.0)
          expect(page.value.history.delta.available).to be(false)
        end
      end

      it "period=all includes every logged row, computing change across the full history" do
        user_inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 1500) ])
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 10.days.ago.to_date, total_value_cents: 1000)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: Date.current, total_value_cents: 1500)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(period: "all"))

        aggregate_failures do
          expect(page.value.history.points.size).to eq(2)
          expect(page.value.history.delta.cents).to eq(500)
          expect(page.value.history.delta.percent).to be_within(0.01).of(50.0)
          expect(page.value.history.delta.available).to be(true)
        end
      end

      it "still returns the live point and zero change when no log rows fall within the window" do
        user_inventory = create(:user_inventory)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 60.days.ago.to_date, total_value_cents: 1000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(period: "7d"))

        aggregate_failures do
          expect(page.value.history.points.size).to eq(1)
          expect(page.value.history.points.first.total_value_cents).to eq(0)
          expect(page.value.history.delta.cents).to eq(0)
          expect(page.value.history.delta.percent).to eq(0.0)
          expect(page.value.history.delta.available).to be(false)
        end
      end

      it "marks the change partial when the baseline row is incomplete" do
        user_inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 200) ])
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 2.days.ago.to_date,
                                      total_value_cents: 100, **partial_counts)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        aggregate_failures do
          expect(page.value.history.delta.cents).to eq(100)
          expect(page.value.history.delta.partial).to be(true)
        end
      end

      it "raises Api::Public::UnsupportedParamError for an unrecognized period value" do
        user_inventory = create(:user_inventory)

        expect { described_class.call(user_inventory.steam_id, ActionController::Parameters.new(period: "bogus")) }
          .to raise_error(Api::Public::UnsupportedParamError, "Unsupported period: bogus")
      end

      it "rejects 24h because inventory value logs are daily" do
        user_inventory = create(:user_inventory)

        expect { described_class.call(user_inventory.steam_id, ActionController::Parameters.new(period: "24h")) }
          .to raise_error(Api::Public::UnsupportedParamError, "Unsupported period: 24h")
      end

      it "keeps total_value_cents from the live valuation regardless of the selected period" do
        user_inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 2000) ])
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 10.days.ago.to_date,
                                      total_value_cents: 1000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(period: "7d"))

        aggregate_failures do
          expect(page.value.snapshot.total_value_cents).to eq(2000)
          expect(page.value.history.points.size).to eq(1)
        end
      end
    end

    describe "top_items" do
      it "defaults sort to price_desc" do
        user_inventory = create(:user_inventory)
        cheap = create(:item, current_price_cents: 100)
        expensive = create(:item, current_price_cents: 900)
        create(:user_inventory_item, user_inventory: user_inventory, item: cheap)
        create(:user_inventory_item, user_inventory: user_inventory, item: expensive)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.items.entries).to eq([ expensive, cheap ])
      end

      it "applies sort=name_asc" do
        user_inventory = create(:user_inventory)
        bravo = create(:item, metadata: { item_name: "Bravo" })
        alpha = create(:item, metadata: { item_name: "Alpha" })
        create(:user_inventory_item, user_inventory: user_inventory, item: bravo)
        create(:user_inventory_item, user_inventory: user_inventory, item: alpha)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(sort: "name_asc"))

        expect(page.items.entries).to eq([ alpha, bravo ])
      end

      it "raises Api::Public::UnsupportedParamError for an unrecognized sort value" do
        user_inventory = create(:user_inventory)

        expect { described_class.call(user_inventory.steam_id, ActionController::Parameters.new(sort: "bogus")) }
          .to raise_error(Api::Public::UnsupportedParamError, "Unsupported sort: bogus")
      end

      it "defaults page/per_page to 1/12 and clamps an oversized per_page to 100" do
        user_inventory = create(:user_inventory)

        default_page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)
        clamped_page = described_class.call(
          user_inventory.steam_id, ActionController::Parameters.new(per_page: "9999")
        )

        aggregate_failures do
          expect(default_page.items.pagination.page).to eq(1)
          expect(default_page.items.pagination.per_page).to eq(12)
          expect(clamped_page.items.pagination.per_page).to eq(100)
        end
      end

      it "fetches trend data for the returned top_items" do
        user_inventory = create(:user_inventory)
        item = create(:item)
        create(:user_inventory_item, user_inventory: user_inventory, item: item)
        create(:price_log, item: item, lowest_price_cents: 4000, created_at: 2.days.ago)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.items.trends[item.market_hash_name]).not_to be_nil
      end
    end
  end

  def partial_counts
    { items_count: 2, pricable_items_count: 2, priced_items_count: 1 }
  end
end
