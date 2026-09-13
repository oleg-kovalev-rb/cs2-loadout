require "rails_helper"

RSpec.describe "POST /api/v1/price_histories", type: :request do
  context "without a bridge token" do
    it "returns unauthorized" do
      post "/api/v1/price_histories", params: { market_hash_names: [ items(:redline).market_hash_name ] }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with a valid token" do
    it "returns price history points for the requested items" do
      token = bridge_token_for("76561198000000001")

      post "/api/v1/price_histories",
        params: { market_hash_names: [ items(:redline).market_hash_name ] }.to_json,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      entry = json["items"].find { |i| i["market_hash_name"] == items(:redline).market_hash_name }

      expect(entry).to be_present
      expect(entry["points"].size).to eq(1)
      expect(entry["points"].first["price_cents"]).to eq(price_logs(:redline_recent).lowest_price_cents)
    end
  end
end
