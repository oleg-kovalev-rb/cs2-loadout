require "rails_helper"

RSpec.describe "Api::Public::Inventories", type: :request do
  describe "GET /api/public/inventories" do
    context "without an Authorization header" do
      it "still succeeds (this endpoint is genuinely public)" do
        get "/api/public/inventories"

        expect(response).to have_http_status(:success)
      end
    end

    context "response shape" do
      let!(:inventory) { create(:user_inventory) }
      let!(:item) do
        create(:item, current_price_cents: 1000, change_24h_cents: 50, metadata: { marketable: true, rarity: "Covert" })
      end

      before { create(:user_inventory_item, user_inventory: inventory, item: item) }

      it "returns meta and inventories with exactly the contracted keys" do
        get "/api/public/inventories"

        json = JSON.parse(response.body)
        inventory_json = json["inventories"].find { |i| i["steam_id"] == inventory.steam_id }

        aggregate_failures do
          expect(json["meta"].keys).to contain_exactly("page", "per_page", "total_count", "total_pages")
          expect(inventory_json.keys).to contain_exactly(
            "steam_id", "total_value_cents", "change_24h_cents", "change_24h_percent",
            "items_count", "pricable_items_count", "priced_items_count", "complete",
            "change_basis_at", "change_partial", "change_available",
            "rarity_mix_percent", "last_synced_at"
          )
          expect(inventory_json["rarity_mix_percent"].keys).to contain_exactly(
            "gold", "covert", "classified", "restricted", "mil_spec", "industrial", "consumer"
          )
        end
      end

      it "derives the 24h change from the previous log and reports a complete card" do
        create(:inventory_value_log,
          steam_id: inventory.steam_id, log_date: 1.day.ago.to_date, total_value_cents: 800,
          items_count: 1, pricable_items_count: 1, priced_items_count: 1)

        get "/api/public/inventories"

        card = JSON.parse(response.body)["inventories"].find { |i| i["steam_id"] == inventory.steam_id }

        aggregate_failures do
          expect(card["change_24h_cents"]).to eq(200)
          expect(card["change_available"]).to be(true)
          expect(card["complete"]).to be(true)
        end
      end

      it "marks the card partial when a marketable item has no price" do
        create(:user_inventory_item, user_inventory: inventory, item: create(:item, :without_price))

        get "/api/public/inventories"

        card = JSON.parse(response.body)["inventories"].find { |i| i["steam_id"] == inventory.steam_id }

        aggregate_failures do
          expect(card["complete"]).to be(false)
          expect(card["priced_items_count"]).to eq(1)
          expect(card["pricable_items_count"]).to eq(2)
        end
      end
    end

    context "search (no-op, since nickname isn't stored in app_fetcher)" do
      let!(:inventory) { create(:user_inventory) }

      it "returns the identical result set whether search is present or absent" do
        get "/api/public/inventories"
        without_search = JSON.parse(response.body)["inventories"]

        get "/api/public/inventories", params: { search: "anything-at-all" }
        with_search = JSON.parse(response.body)["inventories"]

        expect(with_search).to eq(without_search)
      end
    end

    context "sort" do
      let!(:low) { create(:user_inventory) }
      let!(:high) { create(:user_inventory) }

      before { create(:user_inventory_item, user_inventory: high, item: create(:item, current_price_cents: 900)) }

      it "defaults to value_desc" do
        get "/api/public/inventories"

        steam_ids = JSON.parse(response.body)["inventories"].map { |i| i["steam_id"] }
        expect(steam_ids.index(high.steam_id)).to be < steam_ids.index(low.steam_id)
      end

      it "accepts value_asc, ordering low before high" do
        get "/api/public/inventories", params: { sort: "value_asc" }

        steam_ids = JSON.parse(response.body)["inventories"].map { |i| i["steam_id"] }
        expect(steam_ids.index(low.steam_id)).to be < steam_ids.index(high.steam_id)
      end

      it "accepts items_desc and items_asc" do
        many = create(:user_inventory)
        create_list(:item, 2).each { |item| create(:user_inventory_item, user_inventory: many, item: item) }

        get "/api/public/inventories", params: { sort: "items_desc" }
        desc = JSON.parse(response.body)["inventories"].map { |i| i["steam_id"] }
        expect(desc.index(many.steam_id)).to be < desc.index(low.steam_id)

        get "/api/public/inventories", params: { sort: "items_asc" }
        asc = JSON.parse(response.body)["inventories"].map { |i| i["steam_id"] }
        expect(asc.index(many.steam_id)).to be > asc.index(low.steam_id)
      end

      it "rejects the removed recently_synced/change_24h_desc values with :bad_request" do
        %w[recently_synced change_24h_desc].each do |removed|
          get "/api/public/inventories", params: { sort: removed }

          aggregate_failures do
            expect(response).to have_http_status(:bad_request)
            expect(JSON.parse(response.body)["message"]).to eq("Unsupported sort: #{removed}")
          end
        end
      end

      it "rejects an unrecognized sort value with :bad_request" do
        get "/api/public/inventories", params: { sort: "bogus" }

        aggregate_failures do
          expect(response).to have_http_status(:bad_request)
          expect(JSON.parse(response.body)["message"]).to eq("Unsupported sort: bogus")
        end
      end
    end

    context "page/per_page edge cases" do
      it "treats page=0 and non-numeric page as page=1, and clamps an oversized per_page" do
        get "/api/public/inventories", params: { page: "0", per_page: "9999" }

        json = JSON.parse(response.body)
        aggregate_failures do
          expect(json["meta"]["page"]).to eq(1)
          expect(json["meta"]["per_page"]).to eq(100)
        end
      end
    end

    context "caching" do
      let!(:inventory) { create(:user_inventory) }

      it "hits no UserInventory query on a second identical request within the cache TTL" do
        get "/api/public/inventories"

        queries = count_queries(model: UserInventory) { get "/api/public/inventories" }

        expect(queries).to eq(0)
      end
    end

    context "HTTP conditional-GET" do
      let!(:inventory) { create(:user_inventory) }

      it "includes a public, cacheable ETag and returns :not_modified on a matching If-None-Match" do
        get "/api/public/inventories"
        etag = response.headers["ETag"]

        aggregate_failures do
          expect(etag).to be_present
          expect(response.headers["Cache-Control"]).to include("public")
        end

        get "/api/public/inventories", headers: { "If-None-Match" => etag }
        expect(response).to have_http_status(:not_modified)
      end
    end

    context "when an unhandled error escapes the action" do
      it "renders the generic internal-error shape" do
        allow(InventoryCatalogQuery).to receive(:call).and_raise(StandardError, "boom")

        get "/api/public/inventories"

        aggregate_failures do
          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)["message"]).to eq("Internal error")
        end
      end
    end
  end

  describe "GET /api/public/inventories/:steam_id" do
    context "without an Authorization header" do
      let!(:inventory) { create(:user_inventory) }

      it "still succeeds (this endpoint is genuinely public)" do
        get "/api/public/inventories/#{inventory.steam_id}"

        expect(response).to have_http_status(:success)
      end
    end

    context "an unknown steam_id" do
      it "returns 404 with the contracted message" do
        get "/api/public/inventories/unknown-steam-id"

        aggregate_failures do
          expect(response).to have_http_status(:not_found)
          expect(JSON.parse(response.body)["message"]).to eq("Inventory not found")
        end
      end
    end

    context "a synced inventory with zero items" do
      let!(:inventory) { create(:user_inventory) }

      it "returns 200 with all-zero/empty fields, not 404" do
        get "/api/public/inventories/#{inventory.steam_id}"

        json = JSON.parse(response.body)

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json["items_count"]).to eq(0)
          expect(json["avg_item_value_cents"]).to eq(0)
          expect(json["priciest_item"]).to be_nil
          expect(json["top_items"]["entries"]).to eq([])
        end
      end
    end

    context "response shape" do
      let!(:inventory) { create(:user_inventory) }
      let!(:item) do
        create(:item,
          current_price_cents: 4218, change_24h_cents: 130,
          metadata: {
            marketable: true, weapon_type: "AK-47", item_name: "Redline", category: "Rifles",
            condition: "Field-Tested", stattrak: false, icon_url: "https://example.com/icon.png", rarity: "Classified"
          })
      end

      before { create(:user_inventory_item, user_inventory: inventory, item: item) }

      it "returns exactly the contracted top-level keys" do
        get "/api/public/inventories/#{inventory.steam_id}"

        json = JSON.parse(response.body)

        expect(json.keys).to contain_exactly(
          "steam_id", "last_synced_at", "portfolio", "items_count", "avg_item_value_cents",
          "priciest_item", "rarity_breakdown", "top_items"
        )
        expect(json["portfolio"].keys).to contain_exactly(
          "total_value_cents", "change_cents", "change_percent", "change_basis_at",
          "change_partial", "change_available", "complete", "priced_items_count",
          "pricable_items_count", "oldest_price_at", "range", "history"
        )
      end

      it "uses the live total and reports completeness even when a stored log differs" do
        create(:inventory_value_log, steam_id: inventory.steam_id, log_date: Date.current, total_value_cents: 9999)

        get "/api/public/inventories/#{inventory.steam_id}"

        portfolio = JSON.parse(response.body)["portfolio"]

        aggregate_failures do
          expect(portfolio["total_value_cents"]).to eq(4218)
          expect(portfolio["complete"]).to be(true)
          expect(portfolio["priced_items_count"]).to eq(1)
          expect(portfolio["pricable_items_count"]).to eq(1)
        end
      end

      it "marks the portfolio partial when a marketable item has no price" do
        create(:user_inventory_item, user_inventory: inventory, item: create(:item, :without_price))

        get "/api/public/inventories/#{inventory.steam_id}"

        portfolio = JSON.parse(response.body)["portfolio"]

        aggregate_failures do
          expect(portfolio["complete"]).to be(false)
          expect(portfolio["priced_items_count"]).to eq(1)
          expect(portfolio["pricable_items_count"]).to eq(2)
        end
      end

      it "does not leak nickname/avatar_url/steam_level anywhere" do
        get "/api/public/inventories/#{inventory.steam_id}"

        expect(response.body).not_to match(/nickname|avatar_url|steam_level/)
      end
    end

    context "range" do
      let!(:inventory) { create(:user_inventory) }

      it "defaults to 7d" do
        get "/api/public/inventories/#{inventory.steam_id}"

        expect(JSON.parse(response.body)["portfolio"]["range"]).to eq("7d")
      end

      it "accepts range=all" do
        get "/api/public/inventories/#{inventory.steam_id}", params: { range: "all" }

        expect(JSON.parse(response.body)["portfolio"]["range"]).to eq("all")
      end

      it "rejects an unrecognized range value with :bad_request" do
        get "/api/public/inventories/#{inventory.steam_id}", params: { range: "bogus" }

        aggregate_failures do
          expect(response).to have_http_status(:bad_request)
          expect(JSON.parse(response.body)["message"]).to eq("Unsupported range: bogus")
        end
      end
    end

    context "items_sort" do
      let!(:inventory) { create(:user_inventory) }
      let!(:cheap) { create(:item, current_price_cents: 100, metadata: { item_name: "Bravo" }) }
      let!(:expensive) { create(:item, current_price_cents: 900, metadata: { item_name: "Alpha" }) }

      before do
        create(:user_inventory_item, user_inventory: inventory, item: cheap)
        create(:user_inventory_item, user_inventory: inventory, item: expensive)
      end

      it "defaults to price_desc" do
        get "/api/public/inventories/#{inventory.steam_id}"

        names = JSON.parse(response.body)["top_items"]["entries"].map { |e| e["market_hash_name"] }
        expect(names.index(expensive.market_hash_name)).to be < names.index(cheap.market_hash_name)
      end

      it "applies items_sort=name_asc" do
        get "/api/public/inventories/#{inventory.steam_id}", params: { items_sort: "name_asc" }

        names = JSON.parse(response.body)["top_items"]["entries"].map { |e| e["market_hash_name"] }
        expect(names.index(expensive.market_hash_name)).to be < names.index(cheap.market_hash_name)
      end

      it "rejects an unrecognized items_sort value with :bad_request" do
        get "/api/public/inventories/#{inventory.steam_id}", params: { items_sort: "bogus" }

        aggregate_failures do
          expect(response).to have_http_status(:bad_request)
          expect(JSON.parse(response.body)["message"]).to eq("Unsupported items_sort: bogus")
        end
      end
    end

    context "items_page/items_per_page edge cases" do
      let!(:inventory) { create(:user_inventory) }

      it "defaults to page 1/per_page 12 and clamps an oversized items_per_page" do
        get "/api/public/inventories/#{inventory.steam_id}"
        default_meta = JSON.parse(response.body)["top_items"]["meta"]

        get "/api/public/inventories/#{inventory.steam_id}", params: { items_per_page: "9999" }
        clamped_meta = JSON.parse(response.body)["top_items"]["meta"]

        aggregate_failures do
          expect(default_meta["page"]).to eq(1)
          expect(default_meta["per_page"]).to eq(12)
          expect(clamped_meta["per_page"]).to eq(100)
        end
      end
    end

    context "caching" do
      let!(:inventory) { create(:user_inventory) }

      it "hits no UserInventory query on a second identical request within the cache TTL" do
        get "/api/public/inventories/#{inventory.steam_id}"

        queries = count_queries(model: UserInventory) { get "/api/public/inventories/#{inventory.steam_id}" }

        expect(queries).to eq(0)
      end
    end

    context "HTTP conditional-GET" do
      let!(:inventory) { create(:user_inventory) }

      it "includes a public, cacheable ETag and returns :not_modified on a matching If-None-Match" do
        get "/api/public/inventories/#{inventory.steam_id}"
        etag = response.headers["ETag"]

        aggregate_failures do
          expect(etag).to be_present
          expect(response.headers["Cache-Control"]).to include("public")
        end

        get "/api/public/inventories/#{inventory.steam_id}", headers: { "If-None-Match" => etag }
        expect(response).to have_http_status(:not_modified)
      end
    end

    context "when an unhandled error escapes the action" do
      let!(:inventory) { create(:user_inventory) }

      it "renders the generic internal-error shape" do
        allow(InventoryDetailQuery).to receive(:call).and_raise(StandardError, "boom")

        get "/api/public/inventories/#{inventory.steam_id}"

        aggregate_failures do
          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)["message"]).to eq("Internal error")
        end
      end
    end
  end
end
