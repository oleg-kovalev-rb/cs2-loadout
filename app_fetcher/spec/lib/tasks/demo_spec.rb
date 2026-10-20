require "rails_helper"
require "rake"

RSpec.describe "demo:seed_items" do
  subject(:seed_items) { Rake::Task["demo:seed_items"].invoke }

  let(:icon_url) { "https://community.akamai.steamstatic.com/economy/image/seed-icon" }
  let(:entry) do
    {
      "market_hash_name" => "Demo | Seed Test (Field-Tested)",
      "rarity" => "Classified",
      "category" => "Rifle",
      "icon_url" => icon_url
    }
  end

  before do
    Rails.application.load_tasks
    allow(Demo::ItemPool).to receive(:entries).and_return([ entry ])
    Rake::Task["demo:seed_items"].reenable
  end

  it "creates the pool item with its icon and enqueues its price update" do
    expect { seed_items }.to change(Item, :count).by(1)

    item = Item.find_by!(market_hash_name: entry.fetch("market_hash_name"))

    aggregate_failures do
      expect(item.icon_url).to eq(icon_url)
      expect(item.metadata["rarity"]).to eq("Classified")
      expect(item.metadata["category"]).to eq("Rifle")
      expect(PriceUpdateWorker.jobs.map { |job| job["args"].first }).to include(item.id)
    end
  end

  it "backfills missing metadata on an existing item" do
    item = create(
      :item,
      market_hash_name: entry.fetch("market_hash_name"),
      metadata: { marketable: true, tradable: true, icon_url: nil, rarity: nil, category: nil }
    )

    expect { seed_items }.not_to change(Item, :count)

    item.reload

    aggregate_failures do
      expect(item.icon_url).to eq(icon_url)
      expect(item.metadata["rarity"]).to eq("Classified")
      expect(item.metadata["category"]).to eq("Rifle")
    end
  end

  it "does not overwrite populated metadata on an existing item" do
    item = create(
      :item,
      market_hash_name: entry.fetch("market_hash_name"),
      metadata: {
        marketable: true,
        tradable: true,
        icon_url: "https://example.test/custom-icon.png",
        rarity: "Covert",
        category: "Pistol"
      }
    )

    expect { seed_items }.not_to change(Item, :count)

    item.reload

    aggregate_failures do
      expect(item.icon_url).to eq("https://example.test/custom-icon.png")
      expect(item.metadata["rarity"]).to eq("Covert")
      expect(item.metadata["category"]).to eq("Pistol")
    end
  end

  it "is idempotent for an existing item" do
    seed_items
    Rake::Task["demo:seed_items"].reenable

    expect { seed_items }.not_to change(Item, :count)
  end
end
