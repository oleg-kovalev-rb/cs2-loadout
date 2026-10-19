require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "POST /session" do
    it "redirects to Steam OpenID with the callback and realm" do
      post session_path

      redirect = URI.parse(response.location)
      params = URI.decode_www_form(redirect.query).to_h

      aggregate_failures do
        expect(response).to have_http_status(:redirect)
        expect("#{redirect.scheme}://#{redirect.host}#{redirect.path}").to eq(Steam::Authenticator::STEAM_OPENID_URL)
        expect(params["openid.mode"]).to eq("checkid_setup")
        expect(params["openid.return_to"]).to eq(callback_session_url)
        expect(params["openid.realm"]).to eq(root_url)
        expect(params["openid.identity"]).to eq(Steam::Authenticator::IDENTIFIER_SELECT)
        expect(params["openid.claimed_id"]).to eq(Steam::Authenticator::IDENTIFIER_SELECT)
      end
    end
  end

  describe "GET /session/callback" do
    context "when Steam login succeeds" do
      let(:user) { create(:user, nickname: "Oleg") }

      before { allow(Steam::LoginUser).to receive(:call).and_return(user) }

      it "renders a welcome notice after redirecting" do
        get callback_session_path
        follow_redirect!

        aggregate_failures do
          expect(response.body).to include("Welcome, Oleg!")
          expect(response.body).to match(/class="flash flash-notice"[^>]*role="status"/)
        end
      end
    end

    context "when Steam rejects the login" do
      before { allow(Steam::LoginUser).to receive(:call).and_raise(Steam::AuthError, "rejected") }

      it "renders the login failure as an alert after redirecting" do
        get callback_session_path
        follow_redirect!

        aggregate_failures do
          expect(response.body).to include("Login failed. Please try again.")
          expect(response.body).to match(/class="flash flash-alert"[^>]*role="alert"/)
        end
      end
    end
  end

  describe "DELETE /session" do
    it "renders the logout notice after redirecting" do
      delete session_path
      follow_redirect!

      aggregate_failures do
        expect(response.body).to include("Logged out.")
        expect(response.body).to match(/class="flash flash-notice"[^>]*role="status"/)
      end
    end
  end

  describe "a request with no flash" do
    it "renders no flash container" do
      get root_path

      expect(response.body).not_to include("flash-stack")
    end
  end
end
