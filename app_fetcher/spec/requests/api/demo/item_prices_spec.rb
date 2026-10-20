require "rails_helper"

RSpec.describe "Api::Demo::ItemPrices", type: :request do
  let(:showcase_name) { Demo::Inventory.market_hash_names.first }

  def dynamics
    get "/api/demo/item_prices/dynamics",
        headers: { "Authorization" => "Bearer #{demo_token}" }

    JSON.parse(response.body)
  end

  it "returns synthetic current prices for the fixed item set" do
    json = dynamics

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(json["pending_count"]).to eq(0)
      expect(json.dig("prices").size).to eq(30)
      expect(json.dig("prices", showcase_name, "current_price_cents")).to be_positive
    end
  end

  it "returns five-point trends ending at the current price" do
    current_price = dynamics.dig("prices", showcase_name, "current_price_cents")

    get "/api/demo/item_prices/trend",
        headers: { "Authorization" => "Bearer #{demo_token}" }

    trend = JSON.parse(response.body).fetch(showcase_name)

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(trend.size).to eq(5)
      expect(trend.last["price_cents"]).to eq(current_price)
    end
  end

  it "returns generated item history for a known item" do
    current_price = dynamics.dig("prices", showcase_name, "current_price_cents")

    expect {
      get "/api/demo/item_prices/#{ERB::Util.url_encode(showcase_name)}/history",
          params: { period: "7d" },
          headers: { "Authorization" => "Bearer #{demo_token}" }
    }.not_to change(PriceLog, :count)

    json = JSON.parse(response.body)

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(json.size).to eq(8)
      expect(json.last["price_cents"]).to eq(current_price)
    end
  end

  it "supports the 24h history window" do
    get "/api/demo/item_prices/#{ERB::Util.url_encode(showcase_name)}/history",
        params: { period: "24h" },
        headers: { "Authorization" => "Bearer #{demo_token}" }

    expect(JSON.parse(response.body).size).to eq(25)
  end

  it "returns not found for an unknown item" do
    get "/api/demo/item_prices/Unknown%20Item/history",
        headers: { "Authorization" => "Bearer #{demo_token}" }

    aggregate_failures do
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["message"]).to eq("Not found")
    end
  end
end
