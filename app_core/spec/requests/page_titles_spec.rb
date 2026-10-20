require "rails_helper"

RSpec.describe "Page titles", type: :request do
  it "keeps only the product name on the signed-out landing page" do
    get root_path

    expect(response.body).to include("<title>CS2 Loadout</title>")
  end

  it "uses the page name alone, without a brand suffix" do
    get tracked_items_path
    expect(response.body).to include("<title>Items</title>")

    get inventories_path
    expect(response.body).to include("<title>Inventories</title>")

    get inventory_path("76561198000000000")
    expect(response.body).to include("<title>Inventory</title>")
  end

  context "when signed in" do
    let(:user) { create(:user) }

    before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

    it "calls the dashboard My Inventory" do
      get root_path

      expect(response.body).to include("<title>My Inventory</title>")
    end
  end
end
