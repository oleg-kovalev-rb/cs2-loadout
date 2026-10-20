require "rails_helper"

RSpec.describe "GET /demo/inventory", type: :request do
  it "redirects to the root without a demo session" do
    get demo_inventory_path

    expect(response).to redirect_to(root_path)
  end

  context "with a demo session", :demo_redis do
    before { start_demo }

    it "renders the demo inventory detail mount" do
      get demo_inventory_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to include('data-demo-inventory="true"')
        expect(response.body).to include('data-nickname="My account"')
        expect(response.body).to include("My account")
        expect(response.body).to include("badge-demo")
        expect(response.body).not_to include("data-bridge-token")
      end
    end
  end
end
