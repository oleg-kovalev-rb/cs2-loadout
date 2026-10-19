require "rails_helper"

RSpec.describe InventoryListQuery do
  describe ".call" do
    it "aggregates total/items/completeness and derives the 24h change from the baseline log" do
      inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, current_price_cents: 1000, change_24h_cents: 100))
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, current_price_cents: 500, change_24h_cents: -50))
      create(:inventory_value_log,
        steam_id: inventory.steam_id, log_date: 1.day.ago.to_date, total_value_cents: 1200,
        items_count: 2, pricable_items_count: 2, priced_items_count: 2)

      summary = described_class.call(ActionController::Parameters.new).inventories.first

      aggregate_failures do
        expect(summary.steam_id).to eq(inventory.steam_id)
        expect(summary.snapshot.items_count).to eq(2)
        expect(summary.snapshot.pricable_items_count).to eq(2)
        expect(summary.snapshot.priced_items_count).to eq(2)
        expect(summary.delta.cents).to eq(300)
        expect(summary.delta.available).to be(true)
        expect(summary.delta.partial).to be(false)
        expect(summary.delta.basis_at&.to_date&.iso8601).to eq(1.day.ago.to_date.iso8601)
      end
    end

    it "includes a zero-item inventory with all-zero aggregates (left join, not inner join)" do
      empty_inventory = create(:user_inventory)

      summary = described_class.call(ActionController::Parameters.new)
                                .inventories.find { |s| s.steam_id == empty_inventory.steam_id }

      aggregate_failures do
        expect(summary).not_to be_nil
        expect(summary.snapshot.items_count).to eq(0)
        expect(summary.snapshot.total_value_cents).to eq(0)
        expect(summary.snapshot.pricable_items_count).to eq(0)
        expect(summary.snapshot.priced_items_count).to eq(0)
        expect(summary.delta.cents).to eq(0)
        expect(summary.delta.available).to be(false)
        expect(summary.rarity_counts).to eq({})
      end
    end

    it "marks the inventory partial when a pricable item has no price" do
      inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, current_price_cents: 1000))
      create(:user_inventory_item, user_inventory: inventory, item: create(:item, :without_price))

      summary = described_class.call(ActionController::Parameters.new).inventories.first

      aggregate_failures do
        expect(summary.snapshot.pricable_items_count).to eq(2)
        expect(summary.snapshot.priced_items_count).to eq(1)
        expect(summary.delta.partial).to be(true)
      end
    end

    it "marks the change partial when the baseline log is incomplete" do
      inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 1000) ])
      create(:inventory_value_log,
        steam_id: inventory.steam_id, log_date: 1.day.ago.to_date, total_value_cents: 900,
        items_count: 2, pricable_items_count: 2, priced_items_count: 1)

      summary = described_class.call(ActionController::Parameters.new).inventories.first

      expect(summary.delta.partial).to be(true)
    end

    it "makes the change unavailable when the only baseline is older than two days" do
      inventory = create(:user_inventory, items: [ create(:item, current_price_cents: 1000) ])
      create(:inventory_value_log,
        steam_id: inventory.steam_id, log_date: 3.days.ago.to_date, total_value_cents: 900,
        items_count: 1, pricable_items_count: 1, priced_items_count: 1)

      summary = described_class.call(ActionController::Parameters.new).inventories.first

      aggregate_failures do
        expect(summary.delta.available).to be(false)
        expect(summary.delta.cents).to eq(0)
        expect(summary.delta.basis_at&.to_date&.iso8601).to eq(3.days.ago.to_date.iso8601)
      end
    end

    it "total_count reflects every UserInventory regardless of the current page" do
      create_list(:user_inventory, 3)

      page = described_class.call(ActionController::Parameters.new(per_page: "1"))

      expect(page.total_count).to eq(3)
    end

    it "scopes rarity tier counts per inventory without bleeding between inventories" do
      covert_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: covert_inventory, item: create(:item, metadata: { rarity: "Covert" }))
      create(:user_inventory_item, user_inventory: covert_inventory, item: create(:item, metadata: { rarity: "Covert" }))
      classified_inventory = create(:user_inventory)
      create(:user_inventory_item, user_inventory: classified_inventory, item: create(:item, metadata: { rarity: "Classified" }))

      page = described_class.call(ActionController::Parameters.new)
      covert_summary = page.inventories.find { |s| s.steam_id == covert_inventory.steam_id }
      classified_summary = page.inventories.find { |s| s.steam_id == classified_inventory.steam_id }

      aggregate_failures do
        expect(covert_summary.rarity_counts).to eq(RarityTier::Covert => 2)
        expect(classified_summary.rarity_counts).to eq(RarityTier::Classified => 1)
      end
    end

    it "last_synced_at reflects the inventory's own updated_at" do
      inventory = create(:user_inventory)

      summary = described_class.call(ActionController::Parameters.new).inventories.first

      expect(summary.last_synced_at.iso8601).to eq(inventory.updated_at.iso8601)
    end

    describe "sort" do
      it "defaults to value_desc" do
        low = create(:user_inventory)
        create(:user_inventory_item, user_inventory: low, item: create(:item, current_price_cents: 100))
        high = create(:user_inventory)
        create(:user_inventory_item, user_inventory: high, item: create(:item, current_price_cents: 900))

        steam_ids = described_class.call(ActionController::Parameters.new).inventories.map(&:steam_id)

        expect(steam_ids.index(high.steam_id)).to be < steam_ids.index(low.steam_id)
      end

      it "items_desc orders by items_count descending" do
        few = create(:user_inventory)
        create(:user_inventory_item, user_inventory: few, item: create(:item))
        many = create(:user_inventory)
        create_list(:item, 2).each { |item| create(:user_inventory_item, user_inventory: many, item: item) }

        steam_ids = described_class.call(ActionController::Parameters.new(sort: "items_desc")).inventories.map(&:steam_id)

        expect(steam_ids.index(many.steam_id)).to be < steam_ids.index(few.steam_id)
      end

      it "value_asc orders by aggregated total_value_cents ascending" do
        low = create(:user_inventory)
        create(:user_inventory_item, user_inventory: low, item: create(:item, current_price_cents: 100))
        high = create(:user_inventory)
        create(:user_inventory_item, user_inventory: high, item: create(:item, current_price_cents: 900))

        steam_ids = described_class.call(ActionController::Parameters.new(sort: "value_asc")).inventories.map(&:steam_id)

        expect(steam_ids.index(low.steam_id)).to be < steam_ids.index(high.steam_id)
      end

      it "items_asc orders by items_count ascending" do
        few = create(:user_inventory)
        create(:user_inventory_item, user_inventory: few, item: create(:item))
        many = create(:user_inventory)
        create_list(:item, 2).each { |item| create(:user_inventory_item, user_inventory: many, item: item) }

        steam_ids = described_class.call(ActionController::Parameters.new(sort: "items_asc")).inventories.map(&:steam_id)

        expect(steam_ids.index(few.steam_id)).to be < steam_ids.index(many.steam_id)
      end

      it "raises Api::Public::UnsupportedParamError for an unrecognized sort value, without rescuing it" do
        expect { described_class.call(ActionController::Parameters.new(sort: "bogus")) }
          .to raise_error(Api::Public::UnsupportedParamError, "Unsupported sort: bogus")
      end
    end

    describe "pagination" do
      it "defaults to page 1, per_page 24" do
        page = described_class.call(ActionController::Parameters.new)

        aggregate_failures do
          expect(page.pagination.page).to eq(1)
          expect(page.pagination.per_page).to eq(24)
        end
      end

      it "clamps an oversized per_page to the shared max" do
        page = described_class.call(ActionController::Parameters.new(per_page: "9999"))

        expect(page.pagination.per_page).to eq(100)
      end

      it "offsets to the requested page" do
        low = create(:user_inventory)
        create(:user_inventory_item, user_inventory: low, item: create(:item, current_price_cents: 100))
        mid = create(:user_inventory)
        create(:user_inventory_item, user_inventory: mid, item: create(:item, current_price_cents: 200))
        high = create(:user_inventory)
        create(:user_inventory_item, user_inventory: high, item: create(:item, current_price_cents: 300))

        first_page = described_class.call(ActionController::Parameters.new(per_page: "1"))
        second_page = described_class.call(ActionController::Parameters.new(page: "2", per_page: "1"))

        aggregate_failures do
          expect(first_page.inventories.map(&:steam_id)).to eq([ high.steam_id ])
          expect(second_page.inventories.map(&:steam_id)).to eq([ mid.steam_id ])
        end
      end
    end
  end
end
