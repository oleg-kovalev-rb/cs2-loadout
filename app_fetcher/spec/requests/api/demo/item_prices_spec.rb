require "rails_helper"

RSpec.describe "Api::Demo::ItemPrices", type: :request do
  let!(:item) do
    create(
      :item,
      market_hash_name: "Demo | Priced Skin (Field-Tested)",
      current_price_cents: 1_234,
      change_24h_cents: 34,
      price_updated_at: Time.current,
      metadata: { marketable: true, rarity: "Restricted", category: "Pistol" }
    )
  end

  let!(:price_log) do
    create(:price_log, item: item, lowest_price_cents: 1_000, created_at: 2.days.ago)
  end

  before do
    allow(Demo::ItemPool).to receive(:market_hash_names).and_return([ item.market_hash_name ])
  end

  it "returns current prices for the demo item set" do
    get "/api/demo/item_prices/dynamics",
        headers: { "Authorization" => "Bearer #{demo_token}" }

    json = JSON.parse(response.body)

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(json.dig("prices", item.market_hash_name, "current_price_cents")).to eq(1_234)
      expect(json["pending_count"]).to eq(0)
    end
  end

  it "returns trends for the demo item set" do
    get "/api/demo/item_prices/trend",
        headers: { "Authorization" => "Bearer #{demo_token}" }

    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)).to have_key(item.market_hash_name)
  end

  it "returns real item history for a known item" do
    get "/api/demo/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history",
        params: { period: "7d" },
        headers: { "Authorization" => "Bearer #{demo_token}" }

    json = JSON.parse(response.body)

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(json).to be_an(Array)
      expect(json).not_to be_empty
    end
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
