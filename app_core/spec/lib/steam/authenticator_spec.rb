require "rails_helper"

RSpec.describe Steam::Authenticator do
  describe ".auth_url" do
    it "builds the Steam OpenID checkid_setup URL with the given return_to/realm" do
      url = described_class.auth_url("https://app.test/session/callback", "https://app.test")

      uri = URI(url)
      params = URI.decode_www_form(uri.query).to_h

      aggregate_failures do
        expect(uri.to_s).to start_with("https://steamcommunity.com/openid/login?")
        expect(params["openid.ns"]).to eq("http://specs.openid.net/auth/2.0")
        expect(params["openid.mode"]).to eq("checkid_setup")
        expect(params["openid.return_to"]).to eq("https://app.test/session/callback")
        expect(params["openid.realm"]).to eq("https://app.test")
        expect(params["openid.identity"]).to eq("http://specs.openid.net/auth/2.0/identifier_select")
        expect(params["openid.claimed_id"]).to eq("http://specs.openid.net/auth/2.0/identifier_select")
      end
    end
  end

  describe ".validate!" do
    subject(:validate) { described_class.validate!(auth_params) }

    context "with empty auth_params" do
      let(:auth_params) { {} }

      it "raises without making an HTTP call" do
        expect { validate }.to raise_error(Steam::AuthError, "Missing Steam payload")
        expect(WebMock).not_to have_requested(:post, "https://steamcommunity.com/openid/login")
      end
    end

    context "when Steam responds is_valid:false" do
      let(:auth_params) { { "openid.claimed_id" => "https://steamcommunity.com/openid/id/76561198000000001" } }

      before do
        stub_request(:post, "https://steamcommunity.com/openid/login")
          .to_return(status: 200, body: "is_valid:false")
      end

      it "raises a validation-failed AuthError" do
        expect { validate }.to raise_error(Steam::AuthError, "Steam validation failed")
      end
    end

    context "when Steam responds with a non-2xx status" do
      let(:auth_params) { { "openid.claimed_id" => "https://steamcommunity.com/openid/id/76561198000000001" } }

      before do
        stub_request(:post, "https://steamcommunity.com/openid/login")
          .to_return(status: 500, body: "")
      end

      it "raises a validation-failed AuthError" do
        expect { validate }.to raise_error(Steam::AuthError, "Steam validation failed")
      end
    end

    context "when Steam responds is_valid:true but claimed_id has no SteamID64 segment" do
      let(:auth_params) { { "openid.claimed_id" => "https://steamcommunity.com/openid/not-a-steamid" } }

      before do
        stub_request(:post, "https://steamcommunity.com/openid/login")
          .to_return(status: 200, body: "is_valid:true")
      end

      it "raises an invalid-format AuthError" do
        expect { validate }.to raise_error(Steam::AuthError, "Invalid SteamID format")
      end
    end

    context "when Steam responds is_valid:true with a matching claimed_id" do
      let(:auth_params) { { "openid.claimed_id" => "https://steamcommunity.com/openid/id/76561198000000001" } }

      before do
        stub_request(:post, "https://steamcommunity.com/openid/login")
          .to_return(status: 200, body: "is_valid:true")
      end

      it "returns the captured SteamID64" do
        expect(validate).to eq("76561198000000001")
      end
    end

    context "when the transport raises a network error" do
      let(:auth_params) { { "openid.claimed_id" => "https://steamcommunity.com/openid/id/76561198000000001" } }

      [ Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, EOFError ].each do |transport_error|
        context "with #{transport_error}" do
          before do
            stub_request(:post, "https://steamcommunity.com/openid/login").to_raise(transport_error)
          end

          it "wraps it in a network-error AuthError" do
            expect { validate }.to raise_error(Steam::AuthError, /Network error during validation/)
          end
        end
      end
    end
  end
end
