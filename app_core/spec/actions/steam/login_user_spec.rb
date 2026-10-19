require "rails_helper"

RSpec.describe Steam::LoginUser do
  subject(:login) { described_class.call(auth_params) }

  let(:steam_id) { "76561198000000001" }
  let(:auth_params) do
    {
      "openid.mode" => "id_res",
      "openid.claimed_id" => "https://steamcommunity.com/openid/id/#{steam_id}"
    }
  end
  let(:api_key) { "test-steam-api-key" }
  let(:summary_url) { "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("STEAM_WEB_API_KEY", "").and_return(api_key)

    stub_request(:post, Steam::Authenticator::STEAM_OPENID_URL)
      .to_return(status: 200, body: "is_valid:true\n")
  end

  context "when the Steam login and profile lookup succeed" do
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

    it "creates the user with the profile data" do
      user = login

      aggregate_failures do
        expect(User.count).to eq(1)
        expect(user.steam_id).to eq(steam_id)
        expect(user.nickname).to eq("Oleg")
        expect(user.avatar_url).to eq("https://example.com/avatar-full.jpg")
      end
    end
  end

  context "when the user has logged in before" do
    let!(:existing_user) do
      create(:user, steam_id: steam_id, nickname: "Old name", avatar_url: "https://example.com/old.jpg")
    end

    before do
      stub_request(:get, summary_url)
        .with(query: { key: api_key, steamids: steam_id })
        .to_return(
          status: 200,
          body: {
            response: {
              players: [
                { personaname: "New name", avatarfull: "https://example.com/new.jpg" }
              ]
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "updates the existing user instead of creating another" do
      user = login

      aggregate_failures do
        expect(User.count).to eq(1)
        expect(user.id).to eq(existing_user.id)
        expect(user.nickname).to eq("New name")
        expect(user.avatar_url).to eq("https://example.com/new.jpg")
      end
    end
  end

  context "when the profile lookup is unavailable" do
    let(:api_key) { "" }

    it "still creates the user from the Steam ID alone" do
      user = login

      aggregate_failures do
        expect(User.count).to eq(1)
        expect(user.steam_id).to eq(steam_id)
        expect(user.nickname).to be_nil
        expect(user.avatar_url).to be_nil
      end
    end
  end

  context "when Steam rejects the login" do
    before do
      stub_request(:post, Steam::Authenticator::STEAM_OPENID_URL)
        .to_return(status: 200, body: "is_valid:false\n")
    end

    it "propagates the authentication error and persists no user" do
      expect { login }.to raise_error(Steam::AuthError, "Steam validation failed")
      expect(User.count).to eq(0)
    end
  end
end
