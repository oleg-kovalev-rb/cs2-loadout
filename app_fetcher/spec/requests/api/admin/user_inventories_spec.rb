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

    it "does not include an items key on index rows (show-only field)" do
      get "/api/admin/user_inventories", headers: headers

      row = response.parsed_body["user_inventories"].find { |u| u["steam_id"] == user_inventory.steam_id }
      expect(row).not_to have_key("items")
    end

    describe "total_value_cents" do
      it "uses the latest value log per steam_id, nil when none exists" do
        other_inventory = create(:user_inventory)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 2.days.ago.to_date, total_value_cents: 1000)
        create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 1.day.ago.to_date, total_value_cents: 1500)
        # other_inventory has no value log at all.

        get "/api/admin/user_inventories", headers: headers

        expect(response).to have_http_status(:ok)
        rows = response.parsed_body["user_inventories"]
        expect(rows.find { |u| u["steam_id"] == user_inventory.steam_id }["total_value_cents"]).to eq(1500)
        expect(rows.find { |u| u["steam_id"] == other_inventory.steam_id }["total_value_cents"]).to be_nil
      end

      def select_query_count
        count = 0
        callback = lambda do |*_, payload|
          count += 1 if payload[:sql].match?(/\ASELECT/i)
        end

        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
        count
      end

      it "does not N+1 as the number of rows grows" do
        create(:inventory_value_log, steam_id: user_inventory.steam_id)

        small_page_queries = select_query_count { get "/api/admin/user_inventories", headers: headers }

        5.times do
          inventory = create(:user_inventory)
          create(:inventory_value_log, steam_id: inventory.steam_id)
        end

        large_page_queries = select_query_count { get "/api/admin/user_inventories", headers: headers }

        expect(response).to have_http_status(:ok)
        expect(large_page_queries).to eq(small_page_queries)
      end
    end

    describe "pagination" do
      let!(:synced_an_hour_ago) { create(:user_inventory, updated_at: 1.hour.ago) }
      let!(:synced_two_hours_ago) { create(:user_inventory, updated_at: 2.hours.ago) }

      it "includes pagination meta and orders most-recently-synced first" do
        get "/api/admin/user_inventories", headers: headers

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          meta = response.parsed_body["meta"]
          expect(meta["total_count"]).to eq(3)
          steam_ids = response.parsed_body["user_inventories"].map { |u| u["steam_id"] }
          expect(steam_ids).to eq([
            user_inventory.steam_id, synced_an_hour_ago.steam_id, synced_two_hours_ago.steam_id
          ])
        end
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

    it "includes the latest inventory value snapshot" do
      create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 2.days.ago.to_date, total_value_cents: 1000)
      create(:inventory_value_log, steam_id: user_inventory.steam_id, log_date: 1.day.ago.to_date, total_value_cents: 1500)

      get "/api/admin/user_inventories/#{user_inventory.steam_id}", headers: headers

      expect(response.parsed_body["user_inventory"]["total_value_cents"]).to eq(1500)
    end

    it "returns nil total_value_cents when never synced to a value log" do
      get "/api/admin/user_inventories/#{user_inventory.steam_id}", headers: headers

      expect(response.parsed_body["user_inventory"]["total_value_cents"]).to be_nil
    end

    it "includes the inventory's items, newest-added first" do
      older_item = create(:item, market_hash_name: "AWP | Asiimov (Field-Tested)")
      newer_item = create(:item, market_hash_name: "AWP | Dragon Lore (Factory New)")
      create(:user_inventory_item, user_inventory: user_inventory, item: older_item, created_at: 2.days.ago)
      create(:user_inventory_item, user_inventory: user_inventory, item: newer_item, created_at: 1.day.ago)

      get "/api/admin/user_inventories/#{user_inventory.steam_id}", headers: headers

      items = response.parsed_body["user_inventory"]["items"]
      expect(items.map { |i| i["market_hash_name"] }).to eq([ newer_item.market_hash_name, older_item.market_hash_name ])
      expect(items.first).to have_key("added_at")
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

  describe "POST /api/admin/user_inventories/bulk_warm_cache" do
    let!(:inventory_a) { create(:user_inventory) }
    let!(:inventory_b) { create(:user_inventory) }

    it "rejects a valid per-player bridge token" do
      player_token = bridge_token_for(steam_id)

      post "/api/admin/user_inventories/bulk_warm_cache",
           params: { steam_ids: [ inventory_a.steam_id ] },
           headers: { "Authorization" => "Bearer #{player_token}" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "warms the cache for every requested steam_id" do
      post "/api/admin/user_inventories/bulk_warm_cache",
           params: { steam_ids: [ inventory_a.steam_id, inventory_b.steam_id ] },
           headers: headers, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(Rails.cache.exist?([ "user_inventory", 1, inventory_a.steam_id ])).to eq(true)
        expect(Rails.cache.exist?([ "user_inventory", 1, inventory_b.steam_id ])).to eq(true)
        expect(response.parsed_body["warmed_steam_ids"]).to match_array([ inventory_a.steam_id, inventory_b.steam_id ])
      end
    end

    it "silently skips a steam_id that doesn't resolve to a record" do
      post "/api/admin/user_inventories/bulk_warm_cache",
           params: { steam_ids: [ inventory_a.steam_id, "0" ] },
           headers: headers, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["warmed_steam_ids"]).to eq([ inventory_a.steam_id ])
      end
    end
  end
end
