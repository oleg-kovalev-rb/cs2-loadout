require "rails_helper"

RSpec.describe "GET /tracked-items", type: :request do
  describe "when not signed in" do
    it "still renders the catalog mount point (this page needs no sign-in)" do
      get tracked_items_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("tracked-items-root")
        expect(response.body).not_to include("data-bridge-token")
      end
    end

    it "shows the Tracked Items nav tab as active and Portfolio as not" do
      get tracked_items_path

      aggregate_failures do
        expect(response.body).to match(/class="nav-tab is-active"[^>]*>\s*Tracked Items/)
        expect(response.body).to match(/class="nav-tab"[^>]*>Portfolio/)
      end
    end
  end

  describe "when signed in" do
    let(:user) { create(:user) }

    before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

    it "renders the catalog mount point alongside the signed-in topbar" do
      get tracked_items_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("tracked-items-root")
        expect(response.body).to include(user.nickname)
      end
    end
  end
end
