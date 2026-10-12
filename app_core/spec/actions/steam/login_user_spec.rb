require "rails_helper"

RSpec.describe Steam::LoginUser do
  describe ".call" do
    subject(:call) { described_class.call(auth_params) }

    def auth_params_for(steam_id)
      { "openid.claimed_id" => "https://steamcommunity.com/openid/id/#{steam_id}" }
    end

    def stub_valid_steam_auth
      stub_request(:post, "https://steamcommunity.com/openid/login")
        .to_return(status: 200, body: "is_valid:true")
    end

    def stub_steam_profile(nickname:, avatar_url:)
      allow(ENV).to receive(:fetch).with("STEAM_WEB_API_KEY", "").and_return("test-key")
      stub_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries})
        .to_return(status: 200, body: {
          response: { players: [ { "personaname" => nickname, "avatarfull" => avatar_url } ] }
        }.to_json)
    end

    def stub_no_steam_profile
      allow(ENV).to receive(:fetch).with("STEAM_WEB_API_KEY", "").and_return("")
    end

    context "with a new steam_id" do
      let(:auth_params) { auth_params_for("76561198011111111") }

      before do
        stub_valid_steam_auth
        stub_steam_profile(nickname: "NewPlayer", avatar_url: "https://example.com/new.jpg")
      end

      it "creates a user with the fetched profile" do
        expect { call }.to change(User, :count).by(1)

        user = User.find_by(steam_id: "76561198011111111")
        aggregate_failures do
          expect(user.nickname).to eq("NewPlayer")
          expect(user.avatar_url).to eq("https://example.com/new.jpg")
        end
      end
    end

    context "with an existing steam_id" do
      let!(:existing_user) do
        create(:user, steam_id: "76561198022222222", nickname: "OldName", avatar_url: "https://example.com/old.jpg")
      end
      let(:auth_params) { auth_params_for("76561198022222222") }

      before do
        stub_valid_steam_auth
        stub_steam_profile(nickname: "NewName", avatar_url: "https://example.com/new.jpg")
      end

      it "updates the existing user's nickname/avatar instead of creating a new one" do
        expect { call }.not_to change(User, :count)

        existing_user.reload
        aggregate_failures do
          expect(existing_user.nickname).to eq("NewName")
          expect(existing_user.avatar_url).to eq("https://example.com/new.jpg")
        end
      end
    end

    context "when ProfileFetcher returns nil" do
      let!(:existing_user) do
        create(:user, steam_id: "76561198033333333", nickname: "OldName", avatar_url: "https://example.com/old.jpg")
      end
      let(:auth_params) { auth_params_for("76561198033333333") }

      before do
        stub_valid_steam_auth
        stub_no_steam_profile
      end

      it "leaves the existing nickname/avatar untouched" do
        call

        existing_user.reload
        aggregate_failures do
          expect(existing_user.nickname).to eq("OldName")
          expect(existing_user.avatar_url).to eq("https://example.com/old.jpg")
        end
      end
    end

    context "when Steam validation fails" do
      let(:auth_params) { auth_params_for("76561198044444444") }

      before do
        stub_request(:post, "https://steamcommunity.com/openid/login")
          .to_return(status: 200, body: "is_valid:false")
      end

      it "propagates the AuthError uncaught" do
        expect { call }.to raise_error(Steam::AuthError)
      end
    end

    context "when saving the user fails validation" do
      let(:auth_params) { auth_params_for("76561198055555555") }

      before do
        stub_valid_steam_auth
        stub_no_steam_profile
        allow_any_instance_of(User).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(User.new))
      end

      it "propagates the RecordInvalid uncaught" do
        expect { call }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
