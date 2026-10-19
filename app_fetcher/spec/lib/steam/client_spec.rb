require "rails_helper"

RSpec.describe Steam::Client do
  describe "#fetch_item_price" do
    subject(:fetch_price) { described_class.new.fetch_item_price(market_hash_name) }

    let(:market_hash_name) { "AK-47 | Redline (Field-Tested)" }

    context "when Steam returns a successful price overview" do
      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_return(
            status: 200,
            body: {
              success: true,
              lowest_price: "$38.45",
              median_price: "$39.00",
              volume: "1,234"
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the parsed price data" do
        response = fetch_price

        aggregate_failures do
          expect(response.status).to eq(200)
          expect(response).to be_success
          expect(response.data).to have_attributes(
            lowest_price: "$38.45",
            median_price: "$39.00",
            volume: "1,234"
          )
          expect(response.error).to be_nil
        end
      end
    end

    context "when Steam reports that the item has no price" do
      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_return(
            status: 200,
            body: { success: false }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "maps the response to a not-found result" do
        response = fetch_price

        aggregate_failures do
          expect(response.status).to eq(404)
          expect(response).to be_not_found
          expect(response.data).to be_nil
          expect(response.error).to eq("Not Found")
        end
      end
    end

    context "when Steam returns HTTP 429" do
      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_return(status: 429)
      end

      it "maps it to a rate-limit result" do
        response = fetch_price

        aggregate_failures do
          expect(response.status).to eq(429)
          expect(response.error).to eq("Rate Limit Exceeded")
        end
      end
    end

    context "when Steam returns an unexpected HTTP status" do
      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_return(status: 503)
      end

      it "preserves the status and reports a Steam API error" do
        response = fetch_price

        aggregate_failures do
          expect(response.status).to eq(503)
          expect(response.error).to eq("Steam API Error")
        end
      end
    end

    context "when the local rate limiter is exhausted" do
      let(:client) { described_class.new }

      around do |example|
        original = Prop.configurations.fetch(:steam_price_rpm)
        Prop.configure(:steam_price_rpm, original.merge(threshold: 1))
        example.run
      ensure
        Prop.configure(:steam_price_rpm, original)
      end

      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_return(
            status: 200,
            body: { success: true, lowest_price: "$38.45" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns a rate-limit result with retry timing without making a second request" do
        client.fetch_item_price(market_hash_name)
        response = client.fetch_item_price(market_hash_name)

        aggregate_failures do
          expect(response.status).to eq(429)
          expect(response.error).to match(/\ARate Limit Exceeded \(retry after \d+s\)\z/)
          expect(a_request(:get, %r{steamcommunity\.com/market/priceoverview/})).to have_been_made.once
        end
      end
    end

    context "when the HTTP transport fails" do
      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_timeout
      end

      it "maps the failure to a 500 result" do
        response = fetch_price

        aggregate_failures do
          expect(response.status).to eq(500)
          expect(response.data).to be_nil
          expect(response.error).to match(/execution expired|timed out/)
        end
      end
    end

    context "when Steam returns malformed JSON" do
      before do
        stub_request(:get, "https://steamcommunity.com/market/priceoverview/")
          .with(query: { market_hash_name: market_hash_name, appid: "730", currency: "1" })
          .to_return(status: 200, body: "not json", headers: { "Content-Type" => "application/json" })
      end

      it "maps the parse failure to a 500 result" do
        response = fetch_price

        aggregate_failures do
          expect(response.status).to eq(500)
          expect(response.data).to be_nil
          expect(response.error).to match(/unexpected/i)
        end
      end
    end
  end

  describe "#fetch_user_inventory" do
    subject(:fetch_inventory) { described_class.new.fetch_user_inventory(steam_id) }

    let(:steam_id) { "76561198000000001" }

    context "when Steam returns a successful inventory" do
      before do
        stub_request(:get, "https://steamcommunity.com/inventory/#{steam_id}/730/2")
          .with(query: { l: "english", count: "2000" })
          .to_return(
            status: 200,
            body: {
              success: true,
              assets: [ { assetid: "1", classid: "2" } ],
              descriptions: [
                { classid: "2", market_hash_name: "AK-47 | Redline (Field-Tested)" }
              ],
              more_items: false
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the parsed inventory data" do
        response = fetch_inventory

        aggregate_failures do
          expect(response.status).to eq(200)
          expect(response).to be_success
          expect(response.data.assets).to eq([ { "assetid" => "1", "classid" => "2" } ])
          expect(response.data.market_hash_names).to eq([ "AK-47 | Redline (Field-Tested)" ])
          expect(response.data.more_items).to be(false)
        end
      end
    end

    context "when Steam reports the inventory as unavailable" do
      before do
        stub_request(:get, "https://steamcommunity.com/inventory/#{steam_id}/730/2")
          .with(query: { l: "english", count: "2000" })
          .to_return(
            status: 200,
            body: { success: false }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "maps the response to a not-found result" do
        response = fetch_inventory

        aggregate_failures do
          expect(response.status).to eq(404)
          expect(response.data).to be_nil
          expect(response.error).to eq("Not Found")
        end
      end
    end
  end
end
