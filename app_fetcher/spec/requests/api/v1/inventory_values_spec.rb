require "rails_helper"

RSpec.describe "GET /api/v1/inventory_values", type: :request do
  context "without a bridge token" do
    it "returns unauthorized" do
      get "/api/v1/inventory_values"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with a valid token" do
    let(:steam_id) { "76561198000000001" }
    let(:token) { bridge_token_for(steam_id) }
    let(:headers) { { "Authorization" => "Bearer #{token}" } }

    context "with existing log entries for this steam_id" do
      let!(:own_log) { create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 1000) }
      let!(:own_recent_log) { create(:inventory_value_log, steam_id: steam_id, log_date: Date.current, total_value_cents: 1500) }
      let!(:other_users_log) { create(:inventory_value_log, steam_id: "76561198000000099", total_value_cents: 9999) }

      it "returns only this steam_id's points, oldest first, and does not enqueue a seed" do
        get "/api/v1/inventory_values", headers: headers

        json = JSON.parse(response.body)
        points = json["points"]

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(points.size).to eq(2)
          expect(points.map { |p| p["total_value_cents"] }).to eq([ 1000, 1500 ])
          expect(points.map { |p| p["total_value_cents"] }).not_to include(9999)
          expect(InventoryValueUpdateWorker.jobs).to be_empty
        end
      end
    end

    context "with no log entries yet for this steam_id" do
      it "returns an empty list and enqueues a seed for this steam_id" do
        get "/api/v1/inventory_values", headers: headers

        json = JSON.parse(response.body)

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json["points"]).to eq([])
          enqueued_ids = InventoryValueUpdateWorker.jobs.map { |job| job["args"].first }
          expect(enqueued_ids).to eq([ steam_id ])
        end
      end

      it "does not enqueue a duplicate seed on a repeat request within the dedup window" do
        get "/api/v1/inventory_values", headers: headers
        get "/api/v1/inventory_values", headers: headers

        expect(InventoryValueUpdateWorker.jobs.size).to eq(1)
      end
    end
  end
end
