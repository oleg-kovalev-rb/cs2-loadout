require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "POST /session" do
    it "redirects to the Steam OpenID auth URL" do
      post session_path

      expect(response).to redirect_to(Steam::Authenticator.auth_url(callback_session_url, root_url))
    end
  end

  describe "GET /session/callback" do
    context "when LoginUser succeeds" do
      let(:user) { create(:user, nickname: "Oleg") }

      before { allow(Steam::LoginUser).to receive(:call).and_return(user) }

      it "signs the user in and redirects with a welcome notice" do
        get callback_session_path

        aggregate_failures do
          expect(session[:user_id]).to eq(user.id)
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq("Welcome, Oleg!")
        end
      end

      context "when the user has no nickname" do
        let(:user) { create(:user, nickname: nil) }

        it 'falls back to "Player" in the welcome notice' do
          get callback_session_path

          expect(flash[:notice]).to eq("Welcome, Player!")
        end
      end
    end

    context "when Steam validation genuinely fails", :vcr do
      it "redirects with a login-failed alert and does not sign anyone in" do
        get callback_session_path, params: {
          "openid.claimed_id" => "https://steamcommunity.com/openid/id/76561198000000001",
          "openid.mode" => "id_res"
        }

        aggregate_failures do
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("Login failed. Please try again.")
          expect(session[:user_id]).to be_nil
        end
      end
    end

    context "when saving the user fails validation" do
      before { allow(Steam::LoginUser).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(User.new)) }

      it "redirects with an internal-error alert and does not sign anyone in" do
        get callback_session_path

        aggregate_failures do
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("Internal server error during login.")
          expect(session[:user_id]).to be_nil
        end
      end
    end
  end

  describe "DELETE /session" do
    it "clears the session and redirects to the (now signed-out) root" do
      delete session_path

      expect(response).to redirect_to(root_path)
    end
  end
end
