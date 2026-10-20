require "rails_helper"

RSpec.describe "Api::Demo::Inventories", type: :request do
  let(:showcase_name) { Demo::Inventory.market_hash_names.first }

  describe "demo token authentication" do
    it "returns unauthorized without a token" do
      get "/api/demo/inventories"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized for a garbage token" do
      get "/api/demo/inventories", headers: { "Authorization" => "Bearer not-a-token" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized for an expired token" do
      get "/api/demo/inventories",
          headers: { "Authorization" => "Bearer #{demo_token(exp: 1.minute.ago.to_i)}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized for a token with the wrong audience" do
      get "/api/demo/inventories",
          headers: { "Authorization" => "Bearer #{demo_token(aud: 'player')}" }

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["message"]).to eq("Invalid demo token")
      end
    end

    it "returns unauthorized for a player bridge token" do
      player_token = JWT.encode(
        { steam_id: "76561198000000001", exp: 1.hour.from_now.to_i },
        ENV.fetch("APP_BRIDGE_JWT_SECRET"),
        "HS256"
      )

      get "/api/demo/inventories", headers: { "Authorization" => "Bearer #{player_token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/demo/inventories" do
    it "is CORS-reachable from the app_core origin" do
      get "/api/demo/inventories",
          headers: {
            "Authorization" => "Bearer #{demo_token}",
            "Origin" => ENV.fetch("APP_CORE_ORIGIN")
          }

      expect(response.headers["Access-Control-Allow-Origin"]).to eq(ENV.fetch("APP_CORE_ORIGIN"))
    end

    it "serves the dashboard skeleton at /inventories/me" do
      get "/api/demo/inventories/me", headers: { "Authorization" => "Bearer #{demo_token}" }

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)["items"]).to be_an(Array)
      end
    end

    it "returns the fixed showcase without creating domain rows" do
      expect {
        get "/api/demo/inventories", headers: { "Authorization" => "Bearer #{demo_token}" }
      }.not_to change { [ UserInventory.count, PriceLog.count, InventoryValueLog.count ] }

      json = JSON.parse(response.body)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json["items_count"]).to eq(30)
        expect(json["items"].map { |entry| entry["market_hash_name"] }).to include(showcase_name)
      end
    end
  end

  describe "GET /api/demo/inventory_summary" do
    it "returns one entry-shaped inventory summary" do
      get "/api/demo/inventory_summary", headers: { "Authorization" => "Bearer #{demo_token}" }

      json = JSON.parse(response.body)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json).to include(
          "steam_id" => "demo",
          "items_count" => 30,
          "total_value_cents" => be_positive
        )
        expect(json.keys).to include(
          "change_24h_cents",
          "change_24h_percent",
          "pricable_items_count",
          "priced_items_count",
          "complete",
          "rarity_breakdown",
          "last_synced_at"
        )
      end
    end
  end

  describe "GET /api/demo/inventory_detail" do
    it "returns the public detail shape with period and sort applied" do
      get "/api/demo/inventory_detail",
          params: { period: "7d", sort: "price_desc", page: 1, per_page: 30 },
          headers: { "Authorization" => "Bearer #{demo_token}" }

      json = JSON.parse(response.body)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json["steam_id"]).to eq("demo")
        expect(json.dig("portfolio", "period")).to eq("7d")
        expect(json.dig("portfolio", "history")).not_to be_empty
        expect(json.dig("top_items", "entries").map { |entry| entry["market_hash_name"] })
          .to include(showcase_name)
        expect(json["rarity_breakdown"]).to be_an(Array)
      end
    end

    it "rejects an unsupported period" do
      get "/api/demo/inventory_detail",
          params: { period: "3weeks" },
          headers: { "Authorization" => "Bearer #{demo_token}" }

      aggregate_failures do
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["message"]).to eq("Unsupported period: 3weeks")
      end
    end
  end

  describe "token crossover" do
    it "rejects a demo token on the player V1 namespace" do
      get "/api/v1/inventories/me",
          headers: { "Authorization" => "Bearer #{demo_token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
