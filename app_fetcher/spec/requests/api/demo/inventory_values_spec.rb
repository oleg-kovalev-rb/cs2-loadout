require "rails_helper"

RSpec.describe "Api::Demo::InventoryValues", type: :request do
  let!(:item) do
    create(
      :item,
      market_hash_name: "Demo | Value Skin (Field-Tested)",
      current_price_cents: 2_500,
      price_updated_at: Time.current,
      metadata: { marketable: true, rarity: "Covert", category: "Rifle" }
    )
  end

  before do
    allow(Demo::ItemPool).to receive(:market_hash_names).and_return([ item.market_hash_name ])
  end

  it "returns a complete generated history for the requested period" do
    get "/api/demo/inventory_values",
        params: { period: "7d" },
        headers: { "Authorization" => "Bearer #{demo_token}" }

    json = JSON.parse(response.body)

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(json.dig("current", "complete")).to be(true)
      expect(json["history"]).not_to be_empty
      expect(json["history"].last["total_value_cents"]).to eq(json.dig("current", "total_value_cents"))
    end
  end

  it "rejects an unsupported period" do
    get "/api/demo/inventory_values",
        params: { period: "3weeks" },
        headers: { "Authorization" => "Bearer #{demo_token}" }

    aggregate_failures do
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["message"]).to eq("Unsupported period: 3weeks")
    end
  end
end
