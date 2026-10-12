require "rails_helper"

RSpec.describe Steam::ProfileFetcher do
  describe ".call" do
    subject(:call) { described_class.call("76561198000000001") }

    context "when STEAM_WEB_API_KEY is blank" do
      before { allow(ENV).to receive(:fetch).with("STEAM_WEB_API_KEY", "").and_return("") }

      it "returns nil without making an HTTP call" do
        expect(call).to be_nil
        expect(WebMock).not_to have_requested(:get, %r{api\.steampowered\.com})
      end
    end

    context "when STEAM_WEB_API_KEY is present" do
      before { allow(ENV).to receive(:fetch).with("STEAM_WEB_API_KEY", "").and_return("test-key") }

      context "and Steam responds with a non-2xx status" do
        before do
          stub_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries})
            .to_return(status: 500, body: "")
        end

        it "returns nil" do
          expect(call).to be_nil
        end
      end

      context "and Steam responds with no player for the given steam_id" do
        before do
          stub_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries})
            .to_return(status: 200, body: { response: { players: [] } }.to_json)
        end

        it "returns nil" do
          expect(call).to be_nil
        end
      end

      context "and Steam responds with a player" do
        before do
          stub_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries})
            .to_return(status: 200, body: {
              response: { players: [ { "personaname" => "Oleg", "avatarfull" => "https://example.com/avatar.jpg" } ] }
            }.to_json)
        end

        it "returns the nickname/avatar_url" do
          expect(call).to eq(nickname: "Oleg", avatar_url: "https://example.com/avatar.jpg")
        end
      end

      context "and Steam responds with a malformed (non-JSON) body" do
        before do
          stub_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries})
            .to_return(status: 200, body: "not json")
        end

        it "returns nil" do
          expect(call).to be_nil
        end
      end

      context "and the transport raises a timeout" do
        [ Net::OpenTimeout, Net::ReadTimeout ].each do |transport_error|
          context "with #{transport_error}" do
            before do
              stub_request(:get, %r{api\.steampowered\.com/ISteamUser/GetPlayerSummaries}).to_raise(transport_error)
            end

            it "returns nil" do
              expect(call).to be_nil
            end
          end
        end
      end
    end
  end
end
