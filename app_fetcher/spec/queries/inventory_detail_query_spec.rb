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
        expect(page.items_count).to eq(0)
        expect(page.avg_item_value_cents).to eq(0)
        expect(page.priciest_item).to be_nil
        expect(page.rarity_counts).to eq({})
        expect(page.top_items).to eq([])
        expect(page.total_value_cents).to eq(0)
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
      it "reads the latest InventoryValueLog row when one exists" do
        user_inventory = create(:user_inventory)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 2.days.ago.to_date, total_value_cents: 3000)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: Date.current, total_value_cents: 5000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.total_value_cents).to eq(5000)
      end

      it "falls back to a live sum of current item prices when no InventoryValueLog rows exist" do
        user_inventory = create(:user_inventory)
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 1200))
        create(:user_inventory_item, user_inventory: user_inventory, item: create(:item, current_price_cents: 800))

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.total_value_cents).to eq(2000)
      end

      it "does not run the live Item-sum fallback query when an InventoryValueLog row already exists" do
        with_log = create(:user_inventory)
        create(:user_inventory_item, user_inventory: with_log, item: create(:item, current_price_cents: 1000))
        create(:inventory_value_log, steam_id: with_log.steam_id, total_value_cents: 5000)

        without_log = create(:user_inventory)
        create(:user_inventory_item, user_inventory: without_log, item: create(:item, current_price_cents: 1000))

        queries_with_log = count_queries(model: Item) { described_class.call(with_log.steam_id, ActionController::Parameters.new) }
        queries_without_log = count_queries(model: Item) { described_class.call(without_log.steam_id, ActionController::Parameters.new) }

        expect(queries_without_log).to eq(queries_with_log + 1)
      end
    end

    describe "range / history / change_cents / change_percent" do
      it "defaults to 7d, excluding a log older than 7 days" do
        user_inventory = create(:user_inventory)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 10.days.ago.to_date, total_value_cents: 1000)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: Date.current, total_value_cents: 2000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        aggregate_failures do
          expect(page.range).to eq(PricePeriod::SevenDays)
          expect(page.history.size).to eq(1)
          expect(page.history.first.total_value_cents).to eq(2000)
          expect(page.change_cents).to eq(0)
          expect(page.change_percent).to eq(0.0)
        end
      end

      it "range=all includes every logged row, computing change across the full history" do
        user_inventory = create(:user_inventory)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 10.days.ago.to_date, total_value_cents: 1000)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: Date.current, total_value_cents: 1500)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(range: "all"))

        aggregate_failures do
          expect(page.history.size).to eq(2)
          expect(page.change_cents).to eq(500)
          expect(page.change_percent).to be_within(0.01).of(50.0)
        end
      end

      it "returns empty history and zero change when no log rows fall within the window, even if rows exist outside it" do
        user_inventory = create(:user_inventory)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 60.days.ago.to_date, total_value_cents: 1000)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(range: "7d"))

        aggregate_failures do
          expect(page.history).to eq([])
          expect(page.change_cents).to eq(0)
          expect(page.change_percent).to eq(0.0)
        end
      end

      it "raises Api::Public::UnsupportedParamError for an unrecognized range value" do
        user_inventory = create(:user_inventory)

        expect { described_class.call(user_inventory.steam_id, ActionController::Parameters.new(range: "bogus")) }
          .to raise_error(Api::Public::UnsupportedParamError, "Unsupported range: bogus")
      end
    end

    describe "top_items" do
      it "defaults items_sort to price_desc" do
        user_inventory = create(:user_inventory)
        cheap = create(:item, current_price_cents: 100)
        expensive = create(:item, current_price_cents: 900)
        create(:user_inventory_item, user_inventory: user_inventory, item: cheap)
        create(:user_inventory_item, user_inventory: user_inventory, item: expensive)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.top_items).to eq([ expensive, cheap ])
      end

      it "applies items_sort=name_asc" do
        user_inventory = create(:user_inventory)
        bravo = create(:item, metadata: { item_name: "Bravo" })
        alpha = create(:item, metadata: { item_name: "Alpha" })
        create(:user_inventory_item, user_inventory: user_inventory, item: bravo)
        create(:user_inventory_item, user_inventory: user_inventory, item: alpha)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new(items_sort: "name_asc"))

        expect(page.top_items).to eq([ alpha, bravo ])
      end

      it "raises Api::Public::UnsupportedParamError for an unrecognized items_sort value" do
        user_inventory = create(:user_inventory)

        expect { described_class.call(user_inventory.steam_id, ActionController::Parameters.new(items_sort: "bogus")) }
          .to raise_error(Api::Public::UnsupportedParamError, "Unsupported items_sort: bogus")
      end

      it "defaults items_page/items_per_page to 1/12 and clamps an oversized items_per_page to 100" do
        user_inventory = create(:user_inventory)

        default_page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)
        clamped_page = described_class.call(
          user_inventory.steam_id, ActionController::Parameters.new(items_per_page: "9999")
        )

        aggregate_failures do
          expect(default_page.top_items_pagination.page).to eq(1)
          expect(default_page.top_items_pagination.per_page).to eq(12)
          expect(clamped_page.top_items_pagination.per_page).to eq(100)
        end
      end

      it "fetches trend data for the returned top_items" do
        user_inventory = create(:user_inventory)
        item = create(:item)
        create(:user_inventory_item, user_inventory: user_inventory, item: item)
        create(:price_log, item: item, lowest_price_cents: 4000, created_at: 2.days.ago)

        page = described_class.call(user_inventory.steam_id, ActionController::Parameters.new)

        expect(page.trends[item.market_hash_name]).not_to be_nil
      end
    end
  end
end
