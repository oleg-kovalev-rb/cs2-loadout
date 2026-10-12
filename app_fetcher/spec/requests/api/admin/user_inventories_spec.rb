require "rails_helper"

RSpec.describe "Api::Admin::UserInventories", type: :request do
  let(:admin_token) { admin_bridge_token_for("1") }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:steam_id) { "76561198000000099" }

  describe "authentication" do
    it "rejects a request without a bridge token" do
      get "/api/admin/user_inventories"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a valid per-player bridge token" do
      player_token = bridge_token_for(steam_id)

      get "/api/admin/user_inventories", headers: { "Authorization" => "Bearer #{player_token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/admin/user_inventories" do
    let!(:user_inventory) { create(:user_inventory) }

    it "lists user inventories" do
      get "/api/admin/user_inventories", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["user_inventories"].map { |u| u["steam_id"] }).to include(user_inventory.steam_id)
      end
    end
  end

  describe "GET /api/admin/user_inventories/:steam_id" do
    let!(:user_inventory) { create(:user_inventory) }

    it "shows a user inventory" do
      get "/api/admin/user_inventories/#{user_inventory.steam_id}", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["user_inventory"]["steam_id"]).to eq(user_inventory.steam_id)
      end
    end

    it "returns 404 for a non-existent steam_id" do
      get "/api/admin/user_inventories/0", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/admin/user_inventories/:steam_id" do
    let!(:user_inventory) { create(:user_inventory) }

    it "deletes the user inventory" do
      delete "/api/admin/user_inventories/#{user_inventory.steam_id}", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(UserInventory.find_by(steam_id: user_inventory.steam_id)).to be_nil
      end
    end
  end

  describe "POST /api/admin/user_inventories/:steam_id/sync", vcr: true do
    it "syncs the inventory from Steam, creating missing items" do
      post "/api/admin/user_inventories/#{steam_id}/sync", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(UserInventory.find_by(steam_id: steam_id)).to be_present
        expect(Item.find_by(market_hash_name: "AWP | Asiimov (Field-Tested)")).to be_present
      end
    end
  end

  describe "POST /api/admin/user_inventories/:steam_id/warm_cache" do
    let!(:user_inventory) { create(:user_inventory) }

    it "populates the inventory cache" do
      expect(Rails.cache.exist?([ "user_inventory", 1, user_inventory.steam_id ])).to eq(false)

      post "/api/admin/user_inventories/#{user_inventory.steam_id}/warm_cache", headers: headers

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(Rails.cache.exist?([ "user_inventory", 1, user_inventory.steam_id ])).to eq(true)
      end
    end
  end
end
