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

      it "returns only this steam_id's points, oldest first, as a bare array with date/total_value_cents, and does not enqueue a seed" do
        get "/api/v1/inventory_values", headers: headers

        points = JSON.parse(response.body)

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(points.size).to eq(2)
          expect(points.map { |p| p["total_value_cents"] }).to eq([ 1000, 1500 ])
          expect(points.first.keys).to contain_exactly("date", "total_value_cents")
          expect(points.map { |p| p["total_value_cents"] }).not_to include(9999)
          expect(InventoryValueUpdateWorker.jobs).to be_empty
        end
      end
    end

    context "with no log entries yet for this steam_id" do
      let(:priced_item) { create(:item, current_price_cents: 3845) }
      let!(:user_inventory) { create(:user_inventory, steam_id: steam_id, items: [ priced_item ]) }

      it "computes and returns today's value synchronously, with no async job" do
        get "/api/v1/inventory_values", headers: headers

        points = JSON.parse(response.body)

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(points.size).to eq(1)
          expect(points.first["total_value_cents"]).to eq(3845)
          expect(points.first["date"]).to eq(Date.current.iso8601)
          expect(InventoryValueUpdateWorker.jobs).to be_empty
        end
      end

      it "does not create a duplicate row for today on a repeat request" do
        get "/api/v1/inventory_values", headers: headers
        get "/api/v1/inventory_values", headers: headers

        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current).count).to eq(1)
      end
    end

    context "period filtering" do
      let!(:old_log) { create(:inventory_value_log, steam_id: steam_id, log_date: 60.days.ago.to_date, total_value_cents: 100) }
      let!(:mid_log) { create(:inventory_value_log, steam_id: steam_id, log_date: 20.days.ago.to_date, total_value_cents: 200) }
      let!(:recent_log) { create(:inventory_value_log, steam_id: steam_id, log_date: 2.days.ago.to_date, total_value_cents: 300) }

      it "defaults to 'all' (every entry) when period is absent" do
        get "/api/v1/inventory_values", headers: headers

        points = JSON.parse(response.body)
        expect(points.map { |p| p["total_value_cents"] }).to eq([ 100, 200, 300 ])
      end

      it "period=all behaves the same as absent" do
        get "/api/v1/inventory_values?period=all", headers: headers

        points = JSON.parse(response.body)
        expect(points.map { |p| p["total_value_cents"] }).to eq([ 100, 200, 300 ])
      end

      it "period=30d excludes entries older than 30 days" do
        get "/api/v1/inventory_values?period=30d", headers: headers

        points = JSON.parse(response.body)
        expect(points.map { |p| p["total_value_cents"] }).to eq([ 200, 300 ])
      end

      it "period=7d only includes entries within the last 7 days" do
        get "/api/v1/inventory_values?period=7d", headers: headers

        points = JSON.parse(response.body)
        expect(points.map { |p| p["total_value_cents"] }).to eq([ 300 ])
      end

      it "period=1y includes everything in this example set" do
        get "/api/v1/inventory_values?period=1y", headers: headers

        points = JSON.parse(response.body)
        expect(points.map { |p| p["total_value_cents"] }).to eq([ 100, 200, 300 ])
      end

      it "an unsupported period returns bad_request" do
        get "/api/v1/inventory_values?period=3weeks", headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["message"]).to be_present
      end

      it "does not recompute today's row when a narrow period excludes every existing entry" do
        get "/api/v1/inventory_values?period=7d", headers: headers

        recent_log.update!(log_date: 61.days.ago.to_date)

        get "/api/v1/inventory_values?period=7d", headers: headers

        expect(InventoryValueLog.where(steam_id: steam_id, log_date: Date.current)).not_to exist
      end
    end

    context "when an unhandled error escapes the action" do
      before do
        allow_any_instance_of(Api::V1::InventoryValuesController)
          .to receive(:current_steam_id).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:error)
      end

      it "returns a generic internal_server_error body and logs the exception" do
        get "/api/v1/inventory_values", headers: headers

        aggregate_failures do
          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)["message"]).to eq("Internal error")
          expect(Rails.logger).to have_received(:error)
        end
      end
    end
  end
end
