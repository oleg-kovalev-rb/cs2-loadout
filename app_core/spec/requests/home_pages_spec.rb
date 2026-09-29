require "rails_helper"

RSpec.describe "GET /", type: :request do
  context "when not signed in" do
    it "renders the sign-in page" do
      get root_path

      expect(response).to have_http_status(:success)
    end
  end

  context "when signed in" do
    let(:user) { create(:user) }

    before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

    it "redirects straight to the dashboard" do
      get root_path

      expect(response).to redirect_to(dashboard_path)
    end
  end
end
