require "rails_helper"

RSpec.describe DashboardsController, type: :controller do
  render_views

  describe "GET #show" do
    context "when not signed in" do
      it "redirects to root" do
        get :show

        expect(response).to redirect_to(root_path)
      end
    end

    context "when signed in" do
      before { session[:user_id] = users(:one).id }

      it "renders the dashboard page with a bridge token" do
        get :show

        expect(response).to have_http_status(:success)
        expect(response.body).to match(/data-bridge-token="[^"]+"/)
      end
    end
  end
end
