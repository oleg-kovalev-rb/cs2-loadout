require "rails_helper"

RSpec.describe Demo::Inventory do
  subject(:entries) { described_class.entries }

  let(:pool_by_name) do
    Demo::ItemPool.entries.index_by { |entry| entry.fetch("market_hash_name") }
  end

  it "holds the fixed 30-item showcase" do
    expect(entries.size).to eq(30)
  end

  it "has a unique market hash name per entry" do
    names = entries.map(&:market_hash_name)

    expect(names.uniq.size).to eq(names.size)
  end

  it "draws every showcase item from the catalog pool" do
    pool_names = Demo::ItemPool.market_hash_names

    entries.each do |entry|
      expect(pool_names).to include(entry.market_hash_name)
    end
  end

  it "has a positive integer base price for every entry" do
    entries.each do |entry|
      aggregate_failures(entry.market_hash_name) do
        expect(entry.base_price_cents).to be_a(Integer)
        expect(entry.base_price_cents).to be_positive
      end
    end
  end

  it "covers every Steam inventory category" do
    categories = entries.map { |entry| pool_by_name.fetch(entry.market_hash_name).fetch("category") }

    expect(categories.uniq).to contain_exactly(
      "Rifle", "Sniper Rifle", "Pistol", "SMG", "Shotgun", "Machinegun", "Knife", "Gloves"
    )
  end
end
