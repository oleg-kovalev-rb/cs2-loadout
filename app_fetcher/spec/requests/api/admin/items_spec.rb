require "rails_helper"

RSpec.describe "Api::Admin::Items", type: :request do
  let(:admin_token) { admin_bridge_token_for("1") }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }

  describe "authentication" do
    let!(:item) { create(:item) }

    it "rejects a request without a bridge token" do
      get "/api/admin/items"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a garbage token" do
      get "/api/admin/items", headers: { "Authorization" => "Bearer garbage" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired admin token" do
      expired_token = JWT.encode(
        { admin_id: "1", exp: 1.minute.ago.to_i },
        ENV.fetch("APP_ADMIN_BRIDGE_JWT_SECRET"),
        "HS256"
      )

      get "/api/admin/items", headers: { "Authorization" => "Bearer #{expired_token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a valid per-player bridge token" do
      player_token = bridge_token_for("76561198000000001")

      get "/api/admin/items", headers: { "Authorization" => "Bearer #{player_token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/admin/items" do
    let!(:item) { create(:item) }

    it "lists items" do
      get "/api/admin/items", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["items"].map { |i| i["id"] }).to include(item.id)
      end
    end
  end

  describe "GET /api/admin/items/:id" do
    let!(:item) { create(:item) }

    it "shows an item" do
      get "/api/admin/items/#{item.id}", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["item"]["market_hash_name"]).to eq(item.market_hash_name)
      end
    end

    it "returns 404 for a non-existent item" do
      get "/api/admin/items/0", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/admin/items" do
    it "creates an item from just a market_hash_name and enqueues a price refresh" do
      expect {
        post "/api/admin/items", params: { item: { market_hash_name: "AWP | Dragon Lore (Factory New)" } }, headers: headers, as: :json
      }.to change(PriceUpdateWorker.jobs, :size).by(1)

      aggregate_failures do
        expect(response).to have_http_status(:created)
        expect(Item.find_by(market_hash_name: "AWP | Dragon Lore (Factory New)")).to be_present
      end
    end

    it "rejects a blank market_hash_name" do
      post "/api/admin/items", params: { item: { market_hash_name: "" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a duplicate market_hash_name" do
      create(:item, market_hash_name: "AWP | Dragon Lore (Factory New)")

      post "/api/admin/items", params: { item: { market_hash_name: "AWP | Dragon Lore (Factory New)" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/admin/items/:id" do
    let!(:item) { create(:item) }

    it "updates metadata fields" do
      patch "/api/admin/items/#{item.id}", params: { item: { category: "Knives", marketable: true } }, headers: headers, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(item.reload.category).to eq("Knives")
        expect(item.marketable).to eq(true)
      end
    end
  end

  describe "DELETE /api/admin/items/:id" do
    let!(:item) { create(:item) }

    it "deletes the item" do
      delete "/api/admin/items/#{item.id}", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(Item.find_by(id: item.id)).to be_nil
      end
    end
  end

  describe "POST /api/admin/items/:id/refresh_price" do
    let!(:item) { create(:item) }

    it "enqueues PriceUpdateWorker for the item" do
      expect {
        post "/api/admin/items/#{item.id}/refresh_price", headers: headers
      }.to change(PriceUpdateWorker.jobs, :size).by(1)

      aggregate_failures do
        expect(response).to have_http_status(:accepted)
        expect(PriceUpdateWorker.jobs.last["args"]).to eq([ item.id ])
      end
    end
  end

  describe "POST /api/admin/items/:id/warm_cache" do
    let!(:item) { create(:item) }

    it "populates the item's price caches" do
      expect(Rails.cache.exist?([ "item_price", 1, item.market_hash_name ])).to eq(false)

      post "/api/admin/items/#{item.id}/warm_cache", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(Rails.cache.exist?([ "item_price", 1, item.market_hash_name ])).to eq(true)
      end
    end
  end
end
