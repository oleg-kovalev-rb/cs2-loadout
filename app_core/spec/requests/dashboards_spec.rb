require "rails_helper"

RSpec.describe "GET /", type: :request do
  describe "when not signed in" do
    it "renders the signed-out empty state" do
      get root_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Sign in through Steam")
        expect(response.body).not_to include("data-bridge-token")
      end
    end
  end

  describe "when signed in" do
    let(:user) { create(:user) }

    before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

    it "renders the dashboard page with a bridge token" do
      get root_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to match(/data-bridge-token="[^"]+"/)
        expect(response.body).to include(user.nickname)
      end
    end

    it "includes a sign-out control" do
      get root_path

      aggregate_failures do
        expect(response.body).to include("Sign out")
        expect(response.body).to match(/name="_method"\s+value="delete"/)
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
