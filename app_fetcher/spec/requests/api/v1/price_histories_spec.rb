require "rails_helper"

RSpec.describe "POST /api/v1/price_histories", type: :request do
  context "without a bridge token" do
    it "returns unauthorized" do
      post "/api/v1/price_histories", params: { market_hash_names: [ items(:redline).market_hash_name ] }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with a valid token" do
    let(:token) { bridge_token_for("76561198000000001") }

    def post_price_histories(since: nil)
      body = { market_hash_names: [ items(:redline).market_hash_name ] }
      body[:since] = since if since

      post "/api/v1/price_histories",
        params: body.to_json,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    end

    it "returns price history points for the requested items" do
      post_price_histories

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      entry = json["items"].find { |i| i["market_hash_name"] == items(:redline).market_hash_name }

      expect(entry).to be_present
      expect(entry["points"].size).to eq(1)
      expect(entry["points"].first["price_cents"]).to eq(price_logs(:redline_recent).lowest_price_cents)
    end

    it "serves points from cache on a second identical request with no since param" do
      post_price_histories

      queries = count_queries(model: PriceLog) { post_price_histories }

      expect(queries).to eq(0)
    end

    it "queries the DB every time when an explicit since is provided" do
      post_price_histories(since: 10.days.ago.iso8601)

      queries = count_queries(model: PriceLog) { post_price_histories(since: 10.days.ago.iso8601) }

      expect(queries).to eq(1)
    end
  end
end
