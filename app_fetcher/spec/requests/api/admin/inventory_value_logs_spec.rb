require "rails_helper"

RSpec.describe "Api::Admin::InventoryValueLogs", type: :request do
  let(:admin_token) { admin_bridge_token_for("1") }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:steam_id) { "76561198000000055" }

  describe "GET /api/admin/user_inventories/:user_inventory_steam_id/inventory_value_logs" do
    let!(:log) { create(:inventory_value_log, steam_id: steam_id) }
    let!(:other_steam_id_log) { create(:inventory_value_log, steam_id: "76561198000000056") }

    it "rejects a request without a bridge token" do
      get "/api/admin/user_inventories/#{steam_id}/inventory_value_logs"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists only the logs scoped to the steam_id" do
      get "/api/admin/user_inventories/#{steam_id}/inventory_value_logs", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        ids = response.parsed_body["inventory_value_logs"].map { |l| l["id"] }
        expect(ids).to include(log.id)
        expect(ids).not_to include(other_steam_id_log.id)
      end
    end
  end

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

  it "does not expose create/update routes" do
    expect {
      Rails.application.routes.recognize_path(
        "/api/admin/user_inventories/#{steam_id}/inventory_value_logs", method: :post
      )
    }.to raise_error(ActionController::RoutingError)
  end
end
