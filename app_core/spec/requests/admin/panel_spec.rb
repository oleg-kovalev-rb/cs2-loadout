require "rails_helper"

RSpec.describe "GET /admin", type: :request do
  describe "when not signed in" do
    it "redirects to the login page" do
      get admin_panel_path

      expect(response).to redirect_to(new_admin_session_path)
    end
  end

  describe "when signed in as an admin" do
    let!(:admin_user) { create(:admin_user, email: "admin@example.com", password: "correct horse battery staple") }

    before do
      post admin_session_path, params: { email: "admin@example.com", password: "correct horse battery staple" }
    end

    it "renders the panel shell with a non-blank bridge token" do
      get admin_panel_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to match(/data-bridge-token="[^"]+"/)
        expect(response.body).to include("admin@example.com")
      end
    end
  end
end
