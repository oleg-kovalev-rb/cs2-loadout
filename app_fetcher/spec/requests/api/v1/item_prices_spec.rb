require "rails_helper"

RSpec.describe "GET /api/v1/item_prices/dynamics", type: :request do
  let(:steam_id) { "76561198000000001" }
  let(:token) { bridge_token_for(steam_id) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  context "without a bridge token" do
    it "returns unauthorized" do
      get "/api/v1/item_prices/dynamics"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when the steam_id has never been synced" do
    it "returns an empty object" do
      get "/api/v1/item_prices/dynamics", headers: headers

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq({})
    end
  end

  context "with a synced inventory of priced items" do
    let(:priced_item) { create(:item, current_price_cents: 15_050, change_24h_cents: 520) }

    before { create(:user_inventory, steam_id: steam_id, items: [ priced_item ]) }

    it "returns current price, change, and computed percent" do
      get "/api/v1/item_prices/dynamics", headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      aggregate_failures do
        expect(json.keys).to contain_exactly(priced_item.market_hash_name)
        expect(json[priced_item.market_hash_name]["current_price_cents"]).to eq(15_050)
        expect(json[priced_item.market_hash_name]["change_24h_cents"]).to eq(520)
        expect(json[priced_item.market_hash_name]["change_24h_percent"]).to eq(3.58)
      end
    end
  end

  context "when change_24h_cents equals current_price_cents (zero-denominator edge case)" do
    let(:item) { create(:item, current_price_cents: 500, change_24h_cents: 500) }

    before { create(:user_inventory, steam_id: steam_id, items: [ item ]) }

    it "returns a change_24h_percent of 0.0, not Infinity or NaN" do
      get "/api/v1/item_prices/dynamics", headers: headers

      json = JSON.parse(response.body)
      expect(json[item.market_hash_name]["change_24h_percent"]).to eq(0.0)
    end
  end

  context "with an owned item that has no price yet" do
    let!(:unpriced_item) { create(:item, :without_price) }

    before { create(:user_inventory, steam_id: steam_id, items: [ unpriced_item ]) }

    it "omits it from the response" do
      get "/api/v1/item_prices/dynamics", headers: headers

      expect(JSON.parse(response.body)).to eq({})
    end

    it "enqueues a price warmup for it" do
      get "/api/v1/item_prices/dynamics", headers: headers

      enqueued_ids = PriceUpdateWorker.jobs.map { |job| job["args"].first }
      expect(enqueued_ids).to include(unpriced_item.id)
    end

    it "does not enqueue a duplicate job for a repeat request within the dedup window" do
      get "/api/v1/item_prices/dynamics", headers: headers
      get "/api/v1/item_prices/dynamics", headers: headers

      enqueued_for_item = PriceUpdateWorker.jobs.select { |job| job["args"].first == unpriced_item.id }
      expect(enqueued_for_item.size).to eq(1)
    end

    it "caps the number of warmup jobs enqueued per request at 20" do
      extra_unpriced_items = create_list(:item, 20, :without_price)
      all_unpriced = [ unpriced_item ] + extra_unpriced_items
      UserInventory.find_by(steam_id: steam_id).update!(items: all_unpriced)

      get "/api/v1/item_prices/dynamics", headers: headers

      expect(PriceUpdateWorker.jobs.size).to eq(20)
    end
  end
end

RSpec.describe "GET /api/v1/item_prices/trend", type: :request do
  let(:steam_id) { "76561198000000001" }
  let(:token) { bridge_token_for(steam_id) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  context "without a bridge token" do
    it "returns unauthorized" do
      get "/api/v1/item_prices/trend"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when the steam_id has never been synced" do
    it "returns an empty object" do
      get "/api/v1/item_prices/trend", headers: headers

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq({})
    end
  end

  context "with a synced inventory and recent price logs" do
    let(:item) { create(:item) }
    let!(:log) { create(:price_log, item: item, lowest_price_cents: 1000, volume: 5, created_at: 1.day.ago) }

    before { create(:user_inventory, steam_id: steam_id, items: [ item ]) }

    it "returns downsampled trend points for the owned item" do
      get "/api/v1/item_prices/trend", headers: headers

      json = JSON.parse(response.body)

      aggregate_failures do
        expect(json.keys).to contain_exactly(item.market_hash_name)
        expect(json[item.market_hash_name]).not_to be_empty
        expect(json[item.market_hash_name].first).to include("at", "price_cents", "volume")
      end
    end
  end

  context "with an owned item that has no price logs at all" do
    let(:item) { create(:item) }

    before { create(:user_inventory, steam_id: steam_id, items: [ item ]) }

    it "omits it from the response" do
      get "/api/v1/item_prices/trend", headers: headers

      expect(JSON.parse(response.body)).to eq({})
    end
  end
end

RSpec.describe "GET /api/v1/item_prices/:market_hash_name/history", type: :request do
  let(:steam_id) { "76561198000000001" }
  let(:token) { bridge_token_for(steam_id) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  context "without a bridge token" do
    it "returns unauthorized" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode('AK-47 | Redline (Field-Tested)')}/history"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "for an unknown market_hash_name" do
    it "returns an empty array" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode('AK-47 | Unknown (Field-Tested)')}/history", headers: headers

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  context "with an unsupported period" do
    let(:item) { create(:item) }

    it "returns bad_request" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history?period=3weeks", headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["message"]).to be_present
    end
  end

  context "default period (30d, absent)" do
    let(:item) { create(:item) }
    let!(:recent_log) { create(:price_log, item: item, lowest_price_cents: 2000, volume: 3, created_at: 5.days.ago) }
    let!(:old_log) { create(:price_log, item: item, lowest_price_cents: 1500, volume: 1, created_at: 45.days.ago) }

    it "returns points within the default 30-day window, sourced from lowest_price_cents" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history", headers: headers

      points = JSON.parse(response.body)

      aggregate_failures do
        expect(points.size).to eq(1)
        expect(points.first["price_cents"]).to eq(2000)
      end
    end

    it "serves the cached PriceHistoryCache path (no DB hit on a warm cache)" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history", headers: headers

      queries = count_queries(model: PriceLog) do
        get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history", headers: headers
      end

      expect(queries).to eq(0)
    end
  end

  context "an explicit period wider than 30 days" do
    let(:item) { create(:item) }
    let!(:recent_log) { create(:price_log, item: item, lowest_price_cents: 2000, volume: 3, created_at: 5.days.ago) }
    let!(:old_log) { create(:price_log, item: item, lowest_price_cents: 1500, volume: 1, created_at: 45.days.ago) }

    it "bypasses the cache and includes points outside the default window" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history?period=1y", headers: headers

      points = JSON.parse(response.body)
      expect(points.size).to eq(2)
    end
  end

  context "period=24h" do
    let(:item) { create(:item, current_price_cents: 1800) }
    let!(:recent_log) { create(:price_log, item: item, lowest_price_cents: 1800, volume: 2, created_at: 2.hours.ago) }
    let!(:old_log) { create(:price_log, item: item, lowest_price_cents: 1500, volume: 1, created_at: 30.hours.ago) }

    it "returns only the logs within the last 24 hours, with no bucketing" do
      get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history?period=24h", headers: headers

      points = JSON.parse(response.body)

      aggregate_failures do
        expect(points.size).to eq(1)
        expect(points.first["price_cents"]).to eq(1800)
      end
    end

    context "when the item's only log falls outside the 24h window" do
      let(:item) { create(:item, current_price_cents: 3845) }
      let!(:old_log) { create(:price_log, item: item, lowest_price_cents: 1500, volume: 1, created_at: 30.hours.ago) }
      let(:recent_log) { nil }

      it "returns an empty array, with no synthetic current-price point" do
        get "/api/v1/item_prices/#{ERB::Util.url_encode(item.market_hash_name)}/history?period=24h", headers: headers

        expect(JSON.parse(response.body)).to eq([])
      end
    end
  end
end
