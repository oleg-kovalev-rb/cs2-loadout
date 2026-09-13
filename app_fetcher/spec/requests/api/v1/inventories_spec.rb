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
    it "returns the inventory for the steam_id carried in the token, never a client-supplied one" do
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

      token = bridge_token_for("76561198000000001")
      get "/api/v1/inventories/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["items_count"]).to eq(1)
      expect(json["items"].first["market_hash_name"]).to eq(items(:redline).market_hash_name)
      expect(a_request(:get, %r{steamcommunity\.com/inventory/76561198000000001/})).to have_been_made
    end
  end
end
