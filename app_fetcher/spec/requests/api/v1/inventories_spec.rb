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

  context "with a valid token, cold start (no prior sync)" do
    let(:steam_id) { "76561198000000001" }
    let(:token) { bridge_token_for(steam_id) }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [ { classid: "1", market_hash_name: items(:redline).market_hash_name } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns the inventory for the steam_id carried in the token, never a client-supplied one" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["items_count"]).to eq(1)
      expect(json["items"].first["market_hash_name"]).to eq(items(:redline).market_hash_name)
      expect(a_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/})).to have_been_made
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

    it "does not call the Steam API again on a second identical request" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(a_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/})).to have_been_made.once
    end
  end

  context "with a valid token, cold start, unknown item carries an icon" do
    let(:steam_id) { "76561198000000004" }
    let(:token) { bridge_token_for(steam_id) }
    let(:unknown_name) { "AK-47 | Totally Unknown (Field-Tested)" }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [ { classid: "1", market_hash_name: unknown_name, icon_url: "abc123" } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "includes the resolved icon URL in the backfilled item's metadata" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      item_json = JSON.parse(response.body)["items"].first
      expect(item_json["metadata"]["icon_url"]).to eq("https://community.akamai.steamstatic.com/economy/image/abc123")
    end
  end

  context "with a valid token, cold start, unknown item carries marketable/tradable/rarity/category" do
    let(:steam_id) { "76561198000000005" }
    let(:token) { bridge_token_for(steam_id) }
    let(:unknown_name) { "AK-47 | Totally Unknown (Field-Tested)" }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [
              {
                classid: "1",
                market_hash_name: unknown_name,
                marketable: 1,
                tradable: 0,
                tags: [
                  { category: "Type", localized_tag_name: "Rifle" },
                  { category: "Rarity", localized_tag_name: "Classified" }
                ]
              }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

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

  context "with items that have no price yet" do
    let(:steam_id) { "76561198000000002" }
    let(:token) { bridge_token_for(steam_id) }
    let!(:unpriced_item) { create(:item, :without_price) }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [ { classid: "1", market_hash_name: unpriced_item.market_hash_name } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "does not enqueue a price warmup from this endpoint (relocated to item_prices#dynamics)" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(PriceUpdateWorker.jobs).to be_empty
    end
  end

  context "when the Steam call fails" do
    let(:steam_id) { "76561198000000003" }
    let(:token) { bridge_token_for(steam_id) }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "returns the underlying error" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["message"]).to be_present
    end
  end
end

RSpec.describe "POST /api/v1/inventories/refresh", type: :request do
  let(:steam_id) { "76561198000000001" }
  let(:token) { bridge_token_for(steam_id) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  context "without a bridge token" do
    it "returns unauthorized" do
      post "/api/v1/inventories/refresh"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "on a warm inventory" do
    let(:old_item) { create(:item) }
    let(:new_item) { create(:item) }

    before do
      create(:user_inventory, steam_id: steam_id, items: [ old_item ])

      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [ { classid: "1", market_hash_name: new_item.market_hash_name } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "re-fetches from Steam and fully replaces the synced item set" do
      post "/api/v1/inventories/refresh", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["items_count"]).to eq(1)
        expect(json["items"].first.keys).to contain_exactly("market_hash_name", "price_unavailable", "metadata")
        expect(a_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/})).to have_been_made.once
        expect(UserInventory.find_by(steam_id: steam_id).items).to contain_exactly(new_item)
      end
    end

    it "rejects a second refresh for the same steam_id within the same day" do
      post "/api/v1/inventories/refresh", headers: headers
      post "/api/v1/inventories/refresh", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:too_many_requests)
        expect(JSON.parse(response.body)["message"]).to be_present
        expect(a_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/})).to have_been_made.once
      end
    end
  end

  context "on a cold inventory (no prior GET)" do
    let(:item) { create(:item) }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: [ { classid: "1" } ],
            descriptions: [ { classid: "1", market_hash_name: item.market_hash_name } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "still succeeds" do
      post "/api/v1/inventories/refresh", headers: headers

      expect(response).to have_http_status(:success)
    end
  end

  context "when the Steam call fails" do
    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(status: 200, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "returns the underlying error" do
      post "/api/v1/inventories/refresh", headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["message"]).to be_present
    end
  end
end
