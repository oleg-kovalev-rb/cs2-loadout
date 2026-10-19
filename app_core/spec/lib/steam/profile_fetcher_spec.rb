require "rails_helper"

RSpec.describe Steam::ProfileFetcher do
  subject(:fetch_profile) { described_class.call(steam_id) }

  let(:steam_id) { "76561198000000001" }
  let(:api_key) { "test-steam-api-key" }
  let(:summary_url) { "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("STEAM_WEB_API_KEY", "").and_return(api_key)
  end

  context "when the API key is blank" do
    let(:api_key) { "" }

    it "returns nil without calling Steam" do
      expect(fetch_profile).to be_nil
      expect(a_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries/})).not_to have_been_made
    end
  end

  context "when Steam returns a player summary" do
    before do
      stub_request(:get, summary_url)
        .with(query: { key: api_key, steamids: steam_id })
        .to_return(
          status: 200,
          body: {
            response: {
              players: [
                { personaname: "Oleg", avatarfull: "https://example.com/avatar-full.jpg" }
              ]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns the nickname and avatar URL" do
      expect(fetch_profile).to eq(
        nickname: "Oleg",
        avatar_url: "https://example.com/avatar-full.jpg"
      )
    end
  end

  context "when Steam returns a non-success status" do
    before do
      stub_request(:get, summary_url)
        .with(query: { key: api_key, steamids: steam_id })
        .to_return(status: 500)
    end

    it "returns nil" do
      expect(fetch_profile).to be_nil
    end
  end

  context "when Steam returns no players" do
    before do
      stub_request(:get, summary_url)
        .with(query: { key: api_key, steamids: steam_id })
        .to_return(
          status: 200,
          body: { response: { players: [] } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns nil" do
      expect(fetch_profile).to be_nil
    end
  end

  context "when Steam returns malformed JSON" do
    before do
      stub_request(:get, summary_url)
        .with(query: { key: api_key, steamids: steam_id })
        .to_return(status: 200, body: "not json", headers: { "Content-Type" => "application/json" })
    end

    it "returns nil" do
      expect(fetch_profile).to be_nil
    end
  end

  context "when the network times out" do
    before do
      stub_request(:get, summary_url)
        .with(query: { key: api_key, steamids: steam_id })
        .to_timeout
    end

    it "returns nil" do
      expect(fetch_profile).to be_nil
    end
  end
end
