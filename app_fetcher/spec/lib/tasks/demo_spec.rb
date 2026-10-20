require "rails_helper"
require "rake"

RSpec.describe "demo:seed_items" do
  let(:entry) do
    {
      "market_hash_name" => "Demo | Seed Test (Field-Tested)",
      "rarity" => "Classified",
      "category" => "Rifle"
    }
  end

  before do
    Rails.application.load_tasks
    allow(Demo::ItemPool).to receive(:entries).and_return([ entry ])
    Rake::Task["demo:seed_items"].reenable
  end

  it "creates the pool item and enqueues its price update" do
    expect { Rake::Task["demo:seed_items"].invoke }.to change(Item, :count).by(1)

    item = Item.find_by!(market_hash_name: entry.fetch("market_hash_name"))

    aggregate_failures do
      expect(item.metadata["rarity"]).to eq("Classified")
      expect(item.metadata["category"]).to eq("Rifle")
      expect(PriceUpdateWorker.jobs.map { |job| job["args"].first }).to include(item.id)
    end
  end

  it "is idempotent for an existing item" do
    Rake::Task["demo:seed_items"].invoke
    Rake::Task["demo:seed_items"].reenable

    expect { Rake::Task["demo:seed_items"].invoke }.not_to change(Item, :count)
  end
end
