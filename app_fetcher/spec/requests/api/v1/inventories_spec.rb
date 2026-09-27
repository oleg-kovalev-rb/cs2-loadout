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

  context "with a valid token" do
    let(:token) { bridge_token_for("76561198000000001") }

    before do
      stub_request(:get, %r{steamcommunity\.com/inventory/76561198000000001/730/2})
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
      expect(a_request(:get, %r{steamcommunity\.com/inventory/76561198000000001/})).to have_been_made
    end

    it "serves the item's price from cache on a second identical request" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      queries = count_queries(model: Item) do
        get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }
      end

      expect(queries).to eq(0)
    end

    it "does not call the Steam API again on a second identical request" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(a_request(:get, %r{steamcommunity\.com/inventory/76561198000000001/})).to have_been_made.once
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

    it "enqueues PriceUpdateWorker for the unpriced item" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      enqueued_ids = PriceUpdateWorker.jobs.map { |job| job["args"].first }
      expect(enqueued_ids).to include(unpriced_item.id)
    end

    it "does not enqueue a duplicate job for a repeat request within the dedup window" do
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      enqueued_for_item = PriceUpdateWorker.jobs.select { |job| job["args"].first == unpriced_item.id }
      expect(enqueued_for_item.size).to eq(1)
    end

    it "caps the number of warmup jobs enqueued per request at 20" do
      extra_unpriced_items = create_list(:item, 20, :without_price)
      all_unpriced = [ unpriced_item ] + extra_unpriced_items

      stub_request(:get, %r{steamcommunity\.com/inventory/#{steam_id}/730/2})
        .to_return(
          status: 200,
          body: {
            success: 1,
            assets: all_unpriced.each_index.map { |i| { classid: i.to_s } },
            descriptions: all_unpriced.each_with_index.map { |item, i| { classid: i.to_s, market_hash_name: item.market_hash_name } }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(PriceUpdateWorker.jobs.size).to eq(20)
    end
  end
end
