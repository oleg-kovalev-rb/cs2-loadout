require "rails_helper"

RSpec.describe "Api::Admin::PriceLogs", type: :request do
  let(:admin_token) { admin_bridge_token_for("1") }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let!(:item) { create(:item) }

  describe "GET /api/admin/items/:item_id/price_logs" do
    let!(:price_log) { create(:price_log, item: item) }
    let!(:other_item_price_log) { create(:price_log, item: create(:item)) }

    it "rejects a request without a bridge token" do
      get "/api/admin/items/#{item.id}/price_logs"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists only the price logs scoped to the item" do
      get "/api/admin/items/#{item.id}/price_logs", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        ids = response.parsed_body["price_logs"].map { |p| p["id"] }
        expect(ids).to include(price_log.id)
        expect(ids).not_to include(other_item_price_log.id)
      end
    end
  end

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

  it "does not expose create/update routes" do
    expect {
      Rails.application.routes.recognize_path("/api/admin/items/#{item.id}/price_logs", method: :post)
    }.to raise_error(ActionController::RoutingError)
  end
end
