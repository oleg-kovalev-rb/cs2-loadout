require "rails_helper"

RSpec.describe "Api::Admin::PriceLogs", type: :request do
  let(:admin_token) { admin_bridge_token_for("1") }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let!(:item) { create(:item) }

  describe "DELETE /api/admin/items/:item_id/price_logs/:id" do
    let!(:price_log) { create(:price_log, item: item) }

    it "deletes the price log" do
      delete "/api/admin/items/#{item.id}/price_logs/#{price_log.id}", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(PriceLog.find_by(id: price_log.id)).to be_nil
      end
    end

    it "returns 404 for a price log that doesn't belong to the item" do
      other_item = create(:item)

      delete "/api/admin/items/#{other_item.id}/price_logs/#{price_log.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not expose create/update/index routes nested under an item" do
    expect {
      Rails.application.routes.recognize_path("/api/admin/items/#{item.id}/price_logs", method: :post)
    }.to raise_error(ActionController::RoutingError)

    expect {
      Rails.application.routes.recognize_path("/api/admin/items/#{item.id}/price_logs", method: :get)
    }.to raise_error(ActionController::RoutingError)
  end

  describe "GET /api/admin/price_logs" do
    it "rejects a request without a bridge token" do
      get "/api/admin/price_logs"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a valid per-player bridge token" do
      player_token = bridge_token_for("76561198000000001")

      get "/api/admin/price_logs", headers: { "Authorization" => "Bearer #{player_token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists price logs across every item, newest first, with the item's market_hash_name" do
      other_item = create(:item, market_hash_name: "AWP | Dragon Lore (Factory New)")
      log_a = create(:price_log, item: item, created_at: 2.hours.ago)
      log_b = create(:price_log, item: other_item, created_at: 1.hour.ago)

      get "/api/admin/price_logs", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        meta = response.parsed_body["meta"]
        # `>=` rather than an exact count: the global `price_logs(:redline_recent)`
        # fixture (per `config.global_fixtures = :all`) is always present too.
        expect(meta["total_count"]).to be >= 2

        rows = response.parsed_body["price_logs"]
        ids = rows.map { |r| r["id"] }
        expect(ids.index(log_b.id)).to be < ids.index(log_a.id) # newer (log_b) sorts first
        expect(rows.find { |r| r["id"] == log_a.id }["market_hash_name"]).to eq(item.market_hash_name)
        expect(rows.find { |r| r["id"] == log_b.id }["market_hash_name"]).to eq(other_item.market_hash_name)
        expect(rows.find { |r| r["id"] == log_a.id }["item_id"]).to eq(item.id)
        expect(rows.find { |r| r["id"] == log_b.id }["item_id"]).to eq(other_item.id)
      end
    end

    it "does not N+1 across multiple items' logs" do
      3.times { create(:price_log, item: create(:item)) }

      queries = []
      callback = lambda do |*_, payload|
        queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i)
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/api/admin/price_logs", headers: headers
      end

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 3
    end

    it "does not expose create/update/destroy routes" do
      expect {
        Rails.application.routes.recognize_path("/api/admin/price_logs", method: :post)
      }.to raise_error(ActionController::RoutingError)

      expect {
        Rails.application.routes.recognize_path("/api/admin/price_logs/1", method: :delete)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
