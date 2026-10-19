require "rails_helper"

RSpec.describe Steam::Authenticator do
  describe ".auth_url" do
    subject(:auth_url) { described_class.auth_url(return_to, realm) }

    let(:return_to) { "http://www.example.com/session/callback" }
    let(:realm) { "http://www.example.com/" }

    it "builds a Steam OpenID checkid_setup request" do
      uri = URI.parse(auth_url)
      params = URI.decode_www_form(uri.query).to_h

      aggregate_failures do
        expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://steamcommunity.com/openid/login")
        expect(params["openid.ns"]).to eq(described_class::OPENID_NS)
        expect(params["openid.mode"]).to eq("checkid_setup")
        expect(params["openid.return_to"]).to eq(return_to)
        expect(params["openid.realm"]).to eq(realm)
        expect(params["openid.identity"]).to eq(described_class::IDENTIFIER_SELECT)
        expect(params["openid.claimed_id"]).to eq(described_class::IDENTIFIER_SELECT)
      end
    end
  end

  describe ".validate!" do
    subject(:validate) { described_class.validate!(auth_params) }

    let(:steam_id) { "76561198000000001" }
    let(:auth_params) do
      {
        "openid.mode" => "id_res",
        "openid.claimed_id" => "https://steamcommunity.com/openid/id/#{steam_id}"
      }
    end

    context "when Steam confirms the assertion" do
      before do
        stub_request(:post, described_class::STEAM_OPENID_URL)
          .to_return(status: 200, body: "ns:http://specs.openid.net/auth/2.0\nis_valid:true\n")
      end

      it "returns the Steam ID from the claimed identifier" do
        expect(validate).to eq(steam_id)
      end

      it "asks Steam to check the assertion rather than the original mode" do
        validate

        expect(
          a_request(:post, described_class::STEAM_OPENID_URL)
            .with(body: hash_including("openid.mode" => "check_authentication"))
        ).to have_been_made.once
      end
    end

    context "when no parameters are supplied" do
      let(:auth_params) { {} }

      it "rejects the request before calling Steam" do
        expect { validate }.to raise_error(Steam::AuthError, "Missing Steam payload")
      end
    end

    context "when Steam rejects the assertion" do
      before do
        stub_request(:post, described_class::STEAM_OPENID_URL)
          .to_return(status: 200, body: "is_valid:false\n")
      end

      it "raises an authentication error" do
        expect { validate }.to raise_error(Steam::AuthError, "Steam validation failed")
      end
    end

    context "when Steam returns a non-success status" do
      before do
        stub_request(:post, described_class::STEAM_OPENID_URL)
          .to_return(status: 500, body: "is_valid:true\n")
      end

      it "raises an authentication error" do
        expect { validate }.to raise_error(Steam::AuthError, "Steam validation failed")
      end
    end

    context "when the claimed identifier is missing" do
      let(:auth_params) { { "openid.mode" => "id_res" } }

      before do
        stub_request(:post, described_class::STEAM_OPENID_URL)
          .to_return(status: 200, body: "is_valid:true\n")
      end

      it "raises an authentication error" do
        expect { validate }.to raise_error(Steam::AuthError, "Invalid SteamID format")
      end
    end

    context "when the claimed identifier is malformed" do
      let(:auth_params) do
        {
          "openid.mode" => "id_res",
          "openid.claimed_id" => "https://steamcommunity.com/openid/id/not-a-number"
        }
      end

      before do
        stub_request(:post, described_class::STEAM_OPENID_URL)
          .to_return(status: 200, body: "is_valid:true\n")
      end

      it "raises an authentication error" do
        expect { validate }.to raise_error(Steam::AuthError, "Invalid SteamID format")
      end
    end

    context "when the network times out" do
      before do
        stub_request(:post, described_class::STEAM_OPENID_URL)
          .to_raise(Net::OpenTimeout.new("execution expired"))
      end

      it "wraps the network failure in an authentication error" do
        expect { validate }.to raise_error(Steam::AuthError, /Network error during validation: execution expired/)
      end
    end
  end
end
