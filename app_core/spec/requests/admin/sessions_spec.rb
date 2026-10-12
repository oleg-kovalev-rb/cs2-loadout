require "rails_helper"

RSpec.describe "Admin sessions", type: :request do
  describe "POST /admin/session" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    it "signs in with correct credentials and sets the admin session" do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(session[:admin_user_id]).to eq(admin_user.id)
      end
    end

    it "accepts the email case-insensitively" do
      post admin_session_path, params: { email: "ADMIN@EXAMPLE.COM", password: "correct horse battery staple" }

      expect(response).to have_http_status(:ok)
    end

    it "rejects an unknown email" do
      post admin_session_path, params: { email: "nobody@example.com", password: "correct horse battery staple" }

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(session[:admin_user_id]).to be_nil
      end
    end

    it "rejects the wrong password" do
      post admin_session_path, params: { email: "admin@example.com", password: "wrong password" }

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(session[:admin_user_id]).to be_nil
      end
    end

    it "rejects a request with no email param at all" do
      post admin_session_path, params: { password: "correct horse battery staple" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /admin/session" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    it "clears the admin session" do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }
      delete admin_session_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(session[:admin_user_id]).to be_nil
      end
    end

    it "succeeds even with no admin session present" do
      delete admin_session_path

      expect(response).to have_http_status(:ok)
    end
  end
end
