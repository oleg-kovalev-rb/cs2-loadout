require "rails_helper"

RSpec.describe "GET /api/public/items", type: :request do
  context "without an Authorization header" do
    it "still succeeds (this endpoint is genuinely public)" do
      get "/api/public/items"

      expect(response).to have_http_status(:success)
    end
  end

  context "cross-origin request from app_core's browser-side fetch" do
    it "includes an Access-Control-Allow-Origin header for APP_CORE_ORIGIN" do
      get "/api/public/items", headers: { "Origin" => ENV.fetch("APP_CORE_ORIGIN") }

      expect(response.headers["Access-Control-Allow-Origin"]).to eq(ENV.fetch("APP_CORE_ORIGIN"))
    end
  end

  context "with no params, on a catalog of marketable items" do
    let!(:gaining) { create(:item, current_price_cents: 1000, change_24h_cents: 100) }
    let!(:losing) { create(:item, current_price_cents: 900, change_24h_cents: -50) }
    let!(:non_marketable) { create(:item, metadata: { marketable: false }) }

    it "returns only marketable items, defaulted page/per_page, sorted by change_24h_desc" do
      get "/api/public/items"

      json = JSON.parse(response.body)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json["meta"]["page"]).to eq(1)
        expect(json["meta"]["per_page"]).to eq(25)
        names = json["items"].map { |i| i["market_hash_name"] }
        expect(names).to include(gaining.market_hash_name, losing.market_hash_name)
        expect(names).not_to include(non_marketable.market_hash_name)
        expect(names.index(gaining.market_hash_name)).to be < names.index(losing.market_hash_name)
      end
    end
  end

  context "items[].metadata and trend_7d shape" do
    let!(:item) do
      create(:item,
        current_price_cents: 4218, change_24h_cents: 130,
        metadata: {
          marketable: true, tradable: true, souvenir: false, weapon_type: "AK-47", item_name: "Redline",
          category: "Rifles", condition: "Field-Tested", stattrak: false,
          icon_url: "https://example.com/icon.png", rarity: "Classified"
        })
    end
    let!(:log) { create(:price_log, item: item, lowest_price_cents: 4000, created_at: 2.days.ago) }

    it "exposes exactly the 7 contracted metadata keys, no marketable/tradable/souvenir leak" do
      get "/api/public/items"

      item_json = JSON.parse(response.body)["items"].find { |i| i["market_hash_name"] == item.market_hash_name }

      expect(item_json["metadata"].keys).to contain_exactly(
        "weapon_type", "item_name", "category", "condition", "stattrak", "icon_url", "rarity"
      )
    end

    it "computes change_24h_percent and reshapes trend_7d to at/price_cents only" do
      get "/api/public/items"

      item_json = JSON.parse(response.body)["items"].find { |i| i["market_hash_name"] == item.market_hash_name }

      aggregate_failures do
        expect(item_json["current_price_cents"]).to eq(4218)
        expect(item_json["change_24h_cents"]).to eq(130)
        expect(item_json["change_24h_percent"]).to be_within(0.01).of(3.18)
        expect(item_json["trend_7d"]).not_to be_empty
        expect(item_json["trend_7d"].first.keys).to contain_exactly("at", "price_cents")
      end
    end
  end

  context "category[] filtering" do
    let!(:rifle) { create(:item, metadata: { marketable: true, category: "Rifles" }) }
    let!(:knife) { create(:item, metadata: { marketable: true, category: "Knives" }) }

    it "returns only items matching the given category" do
      get "/api/public/items", params: { category: [ "Rifles" ] }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }

      aggregate_failures do
        expect(names).to include(rifle.market_hash_name)
        expect(names).not_to include(knife.market_hash_name)
      end
    end

    it "matches nothing (no error) for an unrecognized category" do
      get "/api/public/items", params: { category: [ "NotARealCategory" ] }

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)["items"]).to eq([])
    end
  end

  context "rarity[] filtering" do
    let!(:classified) { create(:item, metadata: { marketable: true, rarity: "Classified" }) }
    let!(:covert) { create(:item, metadata: { marketable: true, rarity: "Covert" }) }

    it "returns only items matching the given rarity" do
      get "/api/public/items", params: { rarity: [ "Classified" ] }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }

      aggregate_failures do
        expect(names).to include(classified.market_hash_name)
        expect(names).not_to include(covert.market_hash_name)
      end
    end
  end

  context "stattrak filtering" do
    let!(:stattrak_item) { create(:item, metadata: { marketable: true, stattrak: true }) }
    let!(:plain_item) { create(:item, metadata: { marketable: true, stattrak: false }) }

    it "returns only stattrak items when stattrak=true" do
      get "/api/public/items", params: { stattrak: "true" }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }

      aggregate_failures do
        expect(names).to include(stattrak_item.market_hash_name)
        expect(names).not_to include(plain_item.market_hash_name)
      end
    end

    it "returns both when stattrak is absent" do
      get "/api/public/items"

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }
      expect(names).to include(stattrak_item.market_hash_name, plain_item.market_hash_name)
    end

    it "returns both when stattrak=false (not the inverse filter)" do
      get "/api/public/items", params: { stattrak: "false" }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }
      expect(names).to include(stattrak_item.market_hash_name, plain_item.market_hash_name)
    end
  end

  context "search filtering" do
    let!(:redline) { create(:item, metadata: { marketable: true, item_name: "Redline" }) }
    let!(:asiimov) { create(:item, metadata: { marketable: true, item_name: "Asiimov" }) }

    it "matches a case-insensitive substring of item_name" do
      get "/api/public/items", params: { search: "RED" }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }

      aggregate_failures do
        expect(names).to include(redline.market_hash_name)
        expect(names).not_to include(asiimov.market_hash_name)
      end
    end
  end

  context "combined filters" do
    let!(:match) { create(:item, metadata: { marketable: true, category: "Rifles", rarity: "Classified" }) }
    let!(:wrong_category) { create(:item, metadata: { marketable: true, category: "Knives", rarity: "Classified" }) }
    let!(:wrong_rarity) { create(:item, metadata: { marketable: true, category: "Rifles", rarity: "Covert" }) }

    it "applies every given filter together (AND across dimensions)" do
      get "/api/public/items", params: { category: [ "Rifles" ], rarity: [ "Classified" ] }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }

      aggregate_failures do
        expect(names).to include(match.market_hash_name)
        expect(names).not_to include(wrong_category.market_hash_name)
        expect(names).not_to include(wrong_rarity.market_hash_name)
      end
    end
  end

  context "sort" do
    let!(:cheap) { create(:item, current_price_cents: 100, change_24h_cents: -50, metadata: { marketable: true, item_name: "Bravo" }) }
    let!(:expensive) { create(:item, current_price_cents: 900, change_24h_cents: 200, metadata: { marketable: true, item_name: "Alpha" }) }

    it "sorts by price_desc" do
      get "/api/public/items", params: { sort: "price_desc" }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }
      expect(names.index(expensive.market_hash_name)).to be < names.index(cheap.market_hash_name)
    end

    it "sorts by price_asc" do
      get "/api/public/items", params: { sort: "price_asc" }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }
      expect(names.index(cheap.market_hash_name)).to be < names.index(expensive.market_hash_name)
    end

    it "sorts by name_asc" do
      get "/api/public/items", params: { sort: "name_asc" }

      names = JSON.parse(response.body)["items"].map { |i| i["market_hash_name"] }
      expect(names.index(expensive.market_hash_name)).to be < names.index(cheap.market_hash_name)
    end

    it "rejects an unrecognized sort value with :bad_request" do
      get "/api/public/items", params: { sort: "bogus" }

      aggregate_failures do
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["message"]).to eq("Unsupported sort: bogus")
      end
    end
  end

  context "page/per_page edge cases" do
    let!(:items) { create_list(:item, 3, metadata: { marketable: true }) }

    it "treats page=0, page=-1, and non-numeric page as page=1" do
      [ "0", "-1", "abc" ].each do |page_param|
        get "/api/public/items", params: { page: page_param }
        expect(JSON.parse(response.body)["meta"]["page"]).to eq(1)
      end
    end

    it "clamps an oversized per_page to 100" do
      get "/api/public/items", params: { per_page: "9999" }

      expect(JSON.parse(response.body)["meta"]["per_page"]).to eq(100)
    end

    it "returns an empty items array (not an error) for a page past total_pages" do
      get "/api/public/items", params: { page: "999", per_page: "1" }

      json = JSON.parse(response.body)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json["items"]).to eq([])
        expect(json["meta"]["total_count"]).to be >= 3
      end
    end
  end

  context "meta.gaining_count/losing_count scoped to current filters" do
    let!(:gaining_rifle) { create(:item, change_24h_cents: 50, metadata: { marketable: true, category: "Rifles" }) }
    let!(:losing_rifle) { create(:item, change_24h_cents: -50, metadata: { marketable: true, category: "Rifles" }) }
    let!(:flat_rifle) { create(:item, change_24h_cents: 0, metadata: { marketable: true, category: "Rifles" }) }
    let!(:gaining_knife) { create(:item, change_24h_cents: 50, metadata: { marketable: true, category: "Knives" }) }

    it "counts only the filtered set, not the whole catalog" do
      get "/api/public/items", params: { category: [ "Rifles" ] }

      meta = JSON.parse(response.body)["meta"]

      aggregate_failures do
        expect(meta["gaining_count"]).to eq(1)
        expect(meta["losing_count"]).to eq(1)
        expect(meta["total_count"]).to eq(3)
      end
    end
  end

  context "meta.last_synced_at" do
    let!(:item) { create(:item, metadata: { marketable: true }) }

    it "matches the most recent updated_at among marketable items" do
      get "/api/public/items"

      expected = Item.marketable.maximum(:updated_at).iso8601
      expect(JSON.parse(response.body)["meta"]["last_synced_at"]).to eq(expected)
    end
  end

  context "caching" do
    let!(:item) { create(:item, metadata: { marketable: true }) }

    it "hits no Item/PriceLog query on a second identical request within the cache TTL" do
      get "/api/public/items"

      queries = count_queries(model: Item) { get "/api/public/items" }

      expect(queries).to eq(0)
    end
  end

  context "HTTP conditional-GET" do
    let!(:item) { create(:item, metadata: { marketable: true }) }

    it "includes a public, cacheable ETag and returns :not_modified on a matching If-None-Match" do
      get "/api/public/items"
      etag = response.headers["ETag"]

      aggregate_failures do
        expect(etag).to be_present
        expect(response.headers["Cache-Control"]).to include("public")
      end

      get "/api/public/items", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end
  end

  context "when an unhandled error escapes the action" do
    it "renders the generic internal-error shape, independent of Api::V1::'s rescue_from" do
      allow(ItemListQuery).to receive(:call).and_raise(StandardError, "boom")

      get "/api/public/items"

      aggregate_failures do
        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)["message"]).to eq("Internal error")
      end
    end
  end
end
