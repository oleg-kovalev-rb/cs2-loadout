require "rails_helper"

RSpec.describe "Api::Admin::InventoryValueLogs", type: :request do
  let(:admin_token) { admin_bridge_token_for("1") }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:steam_id) { "76561198000000055" }

  describe "DELETE /api/admin/user_inventories/:user_inventory_steam_id/inventory_value_logs/:id" do
    let!(:log) { create(:inventory_value_log, steam_id: steam_id) }

    it "deletes the log" do
      delete "/api/admin/user_inventories/#{steam_id}/inventory_value_logs/#{log.id}", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(InventoryValueLog.find_by(id: log.id)).to be_nil
      end
    end

    it "returns 404 for a log that doesn't belong to the steam_id" do
      delete "/api/admin/user_inventories/76561198000000056/inventory_value_logs/#{log.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not expose create/update/index routes nested under a user_inventory" do
    expect {
      Rails.application.routes.recognize_path(
        "/api/admin/user_inventories/#{steam_id}/inventory_value_logs", method: :post
      )
    }.to raise_error(ActionController::RoutingError)

    expect {
      Rails.application.routes.recognize_path(
        "/api/admin/user_inventories/#{steam_id}/inventory_value_logs", method: :get
      )
    }.to raise_error(ActionController::RoutingError)
  end

  describe "GET /api/admin/inventory_value_logs" do
    it "rejects a request without a bridge token" do
      get "/api/admin/inventory_value_logs"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a valid per-player bridge token" do
      player_token = bridge_token_for(steam_id)

      get "/api/admin/inventory_value_logs", headers: { "Authorization" => "Bearer #{player_token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists logs across every steam_id, newest first, with each row's steam_id" do
      other_steam_id = "76561198000000077"
      log_a = create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date)
      log_b = create(:inventory_value_log, steam_id: other_steam_id, log_date: 1.day.ago.to_date)

      get "/api/admin/inventory_value_logs", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        meta = response.parsed_body["meta"]
        expect(meta["total_count"]).to eq(2)

        rows = response.parsed_body["inventory_value_logs"]
        ids = rows.map { |r| r["id"] }
        expect(ids.index(log_b.id)).to be < ids.index(log_a.id)
        expect(rows.find { |r| r["id"] == log_a.id }["steam_id"]).to eq(steam_id)
        expect(rows.find { |r| r["id"] == log_b.id }["steam_id"]).to eq(other_steam_id)
      end
    end

    it "does not N+1 across many distinct steam_ids on one page" do
      6.times { |n| create(:inventory_value_log, steam_id: "7656119800000#{10 + n}") }

      queries = []
      callback = lambda do |*_, payload|
        queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i)
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/api/admin/inventory_value_logs", headers: headers
      end

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 2
    end

    it "does not expose create/update/destroy routes" do
      expect {
        Rails.application.routes.recognize_path("/api/admin/inventory_value_logs", method: :post)
      }.to raise_error(ActionController::RoutingError)

      expect {
        Rails.application.routes.recognize_path("/api/admin/inventory_value_logs/1", method: :delete)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
