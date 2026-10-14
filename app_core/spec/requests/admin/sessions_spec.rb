require "rails_helper"

RSpec.describe "Admin sessions", type: :request do
  describe "POST /admin/session (format.json, existing behavior unchanged)" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    it "signs in with correct credentials and sets the admin session" do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(session[:admin_user_id]).to eq(admin_user.id)
      end
    end

    it "accepts the email case-insensitively" do
      post admin_session_path, params: { email: "ADMIN@EXAMPLE.COM", password: "correct horse battery staple" }, as: :json

      expect(response).to have_http_status(:ok)
    end

    it "rejects an unknown email" do
      post admin_session_path, params: { email: "nobody@example.com", password: "correct horse battery staple" }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(session[:admin_user_id]).to be_nil
      end
    end

    it "rejects the wrong password" do
      post admin_session_path, params: { email: "admin@example.com", password: "wrong password" }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(session[:admin_user_id]).to be_nil
      end
    end

    it "rejects a request with no email param at all" do
      post admin_session_path, params: { password: "correct horse battery staple" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /admin/session (format.json, existing behavior unchanged)" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    it "clears the admin session" do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }, as: :json
      delete admin_session_path, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(session[:admin_user_id]).to be_nil
      end
    end

    it "succeeds even with no admin session present" do
      delete admin_session_path, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/session/new" do
    it "renders the login form" do
      get new_admin_session_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<form")
        expect(response.body).to include("email")
        expect(response.body).to include("password")
      end
    end
  end

  describe "POST /admin/session (format.html)" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    it "signs in and redirects to the admin panel on success" do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }

      aggregate_failures do
        expect(response).to redirect_to(admin_panel_path)
        expect(session[:admin_user_id]).to eq(admin_user.id)
      end
    end

    it "re-renders the login form with an error on bad credentials" do
      post admin_session_path, params: { email: "admin@example.com", password: "wrong password" }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid email or password")
        expect(session[:admin_user_id]).to be_nil
      end
    end
  end

  describe "DELETE /admin/session (format.html)" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    it "clears the session and redirects to the login page" do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }
      delete admin_session_path

      aggregate_failures do
        expect(response).to redirect_to(new_admin_session_path)
        expect(session[:admin_user_id]).to be_nil
      end
    end
  end
end
