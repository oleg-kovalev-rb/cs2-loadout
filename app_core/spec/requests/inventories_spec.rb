require "rails_helper"

RSpec.describe "GET /inventories", type: :request do
  it "renders successfully when signed out, with no bridge token" do
    get inventories_path

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("data-bridge-token")
      expect(response.body).to match(%r{<a[^>]+class="nav-tab is-active"[^>]*>\s*Inventories\s*</a>})
    end
  end

  describe "when signed in" do
    let(:user) { create(:user) }

    before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

    it "still renders without a bridge token, keeping the topbar's signed-in chrome" do
      get inventories_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("data-bridge-token")
        expect(response.body).to include(user.nickname)
      end
    end
  end
end

RSpec.describe "GET /inventories/:steam_id", type: :request do
  it "renders successfully for any steam_id, with no bridge token" do
    get inventory_path("76561198000000000")

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("data-bridge-token")
      expect(response.body).to match(%r{<a[^>]+class="nav-tab is-active"[^>]*>\s*Inventories\s*</a>})
      expect(response.body).to include('data-steam-id="76561198000000000"')
    end
  end
end

RSpec.describe "shared topbar nav tabs", type: :request do
  it "marks Portfolio active on the dashboard and Inventories active on the inventories pages" do
    get root_path
    expect(response.body).to match(%r{<a[^>]+class="nav-tab is-active"[^>]*>\s*Portfolio\s*</a>})

    get inventories_path
    expect(response.body).to match(%r{<a[^>]+class="nav-tab is-active"[^>]*>\s*Inventories\s*</a>})
  end
end
