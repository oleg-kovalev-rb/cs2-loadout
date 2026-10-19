require "rails_helper"

RSpec.describe "GET /api/v1/inventories/me", type: :request do
  context "without a bridge token" do
    it "returns unauthorized" do
      get "/api/v1/inventories/me"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with a garbage token" do
    it "returns unauthorized" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer not-a-real-token" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with an expired token" do
    it "returns unauthorized" do
      expired = JWT.encode({ steam_id: "111", exp: 1.minute.ago.to_i }, ENV.fetch("APP_BRIDGE_JWT_SECRET"), "HS256")

      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{expired}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with a valid token that has no steam_id claim" do
    it "returns unauthorized" do
      token = JWT.encode({ exp: 2.minutes.from_now.to_i }, ENV.fetch("APP_BRIDGE_JWT_SECRET"), "HS256")

      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["message"]).to eq("Invalid bridge token")
      end
    end
  end

  context "with a valid token whose steam_id claim is not a string" do
    it "returns unauthorized" do
      token = JWT.encode({ steam_id: 123, exp: 2.minutes.from_now.to_i }, ENV.fetch("APP_BRIDGE_JWT_SECRET"), "HS256")

      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["message"]).to eq("Invalid bridge token")
      end
    end
  end

  context "with a valid token, cold start (no prior sync)",
          vcr: { cassette_name: "api_v1_inventories/cold_start" } do
    let(:steam_id) { "76561198000000001" }
    let(:token) { bridge_token_for(steam_id) }

    it "returns the inventory for the steam_id carried in the token, never a client-supplied one" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["items_count"]).to eq(1)
      expect(json["items"].first["market_hash_name"]).to eq(items(:redline).market_hash_name)
    end

    it "does not include price values, but exposes the price_unavailable flag" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      item_json = JSON.parse(response.body)["items"].first

      aggregate_failures do
        expect(item_json.keys).to contain_exactly("market_hash_name", "price_unavailable", "metadata")
        expect(item_json["price_unavailable"]).to be(false)
      end
    end

    it "exposes a true price_unavailable flag for an unavailable item" do
      items(:redline).update!(price_unavailable: true)
      UserInventoryCache.invalidate(steam_id)

      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(JSON.parse(response.body)["items"].first["price_unavailable"]).to be(true)
    end

    it "persists the user's inventory to the DB before responding" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(items(:redline))
    end

    it "does not sync again on a second identical request" do
      expect(UserInventorySyncService).to receive(:call).once.and_call_original

      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
    end
  end

  context "with a valid token, cold start, unknown item carries an icon",
          vcr: { cassette_name: "api_v1_inventories/unknown_item_icon" } do
    let(:steam_id) { "76561198000000004" }
    let(:token) { bridge_token_for(steam_id) }
    let(:unknown_name) { "AK-47 | Totally Unknown (Field-Tested)" }

    it "includes the resolved icon URL in the backfilled item's metadata" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      item_json = JSON.parse(response.body)["items"].first
      expect(item_json["metadata"]["icon_url"]).to eq("https://community.akamai.steamstatic.com/economy/image/abc123")
    end
  end

  context "with a valid token, cold start, unknown item carries marketable/tradable/rarity/category",
          vcr: { cassette_name: "api_v1_inventories/unknown_item_metadata" } do
    let(:steam_id) { "76561198000000005" }
    let(:token) { bridge_token_for(steam_id) }
    let(:unknown_name) { "AK-47 | Totally Unknown (Field-Tested)" }

    it "includes the resolved marketable/tradable/rarity/category values in the backfilled item's metadata" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      item_json = JSON.parse(response.body)["items"].first

      aggregate_failures do
        expect(item_json["metadata"]["marketable"]).to be(true)
        expect(item_json["metadata"]["tradable"]).to be(false)
        expect(item_json["metadata"]["rarity"]).to eq("Classified")
        expect(item_json["metadata"]["category"]).to eq("Rifle")
      end
    end
  end

  context "with a valid token, already synced and cache-warm" do
    let(:steam_id) { "76561198000000001" }
    let(:token) { bridge_token_for(steam_id) }
    let(:item) { create(:item) }

    before do
      create(:user_inventory, steam_id: steam_id, items: [ item ])
      UserInventoryCache.fetch(steam_id)
    end

    it "serves the response without calling Steam or querying the DB" do
      queries = count_queries(model: Item) do
        get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }
      end

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)["items_count"]).to eq(1)
        expect(a_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/})).not_to have_been_made
        expect(queries).to eq(0)
      end
    end
  end

  context "with items that have no price yet",
          vcr: { cassette_name: "api_v1_inventories/unpriced_item" } do
    let(:steam_id) { "76561198000000002" }
    let(:token) { bridge_token_for(steam_id) }
    let!(:unpriced_item) do
      create(:item, :without_price, market_hash_name: "AK-47 | Unpriced Test (Field-Tested)")
    end

    it "does not enqueue a price warmup from this endpoint (relocated to item_prices#dynamics)" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(PriceUpdateWorker.jobs).to be_empty
    end
  end

  context "when the Steam call fails",
          vcr: { cassette_name: "api_v1_inventories/steam_failure" } do
    let(:steam_id) { "76561198000000003" }
    let(:token) { bridge_token_for(steam_id) }

    it "returns the underlying error" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["message"]).to be_present
    end
  end
end
