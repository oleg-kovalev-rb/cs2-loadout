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

  it "embeds the nickname/avatar when app_core knows the steam_id" do
    create(:user, steam_id: "76561198000000042", nickname: "Ada", avatar_url: "https://example.com/a.jpg")

    get inventory_path("76561198000000042")

    aggregate_failures do
      expect(response.body).to include('data-nickname="Ada"')
      expect(response.body).to include('data-avatar-url="https://example.com/a.jpg"')
    end
  end

  it "embeds blank profile attributes when app_core doesn't know the steam_id" do
    get inventory_path("76561198000000000")

    aggregate_failures do
      expect(response.body).to include('data-nickname=""')
      expect(response.body).to include('data-avatar-url=""')
    end
  end
end

RSpec.describe "GET /inventories/profiles", type: :request do
  it "returns a profile map for the requested steam_ids that exist, with no auth header" do
    create(:user, steam_id: "76561198111111111", nickname: "Ada", avatar_url: "https://example.com/a.jpg")
    create(:user, steam_id: "76561198222222222", nickname: "Grace", avatar_url: nil)

    get "/inventories/profiles",
        params: { steam_ids: %w[76561198111111111 76561198333333333 76561198222222222] }

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)["profiles"]).to eq(
        "76561198111111111" => { "nickname" => "Ada", "avatar_url" => "https://example.com/a.jpg" },
        "76561198222222222" => { "nickname" => "Grace", "avatar_url" => nil }
      )
    end
  end

  it "returns an empty map when no steam_ids are given" do
    get "/inventories/profiles"

    aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)["profiles"]).to eq({})
    end
  end

  it "caps the requested steam_ids at 100" do
    steam_ids = Array.new(101) { |n| format("cap-%03d", n) }
    steam_ids.each { |steam_id| create(:user, steam_id: steam_id) }

    get "/inventories/profiles", params: { steam_ids: steam_ids }

    expect(JSON.parse(response.body)["profiles"].keys).to have_attributes(size: 100)
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
