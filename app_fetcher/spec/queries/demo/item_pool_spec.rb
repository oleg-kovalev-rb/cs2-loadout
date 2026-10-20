require "rails_helper"

RSpec.describe Demo::ItemPool do
  subject(:entries) { described_class.entries }

  let(:known_categories) do
    [ "Rifle", "Sniper Rifle", "Pistol", "SMG", "Shotgun", "Machinegun", "Knife", "Gloves" ]
  end

  describe ".entries" do
    it "holds a curated pool of 40 to 50 items" do
      expect(entries.size).to be_between(40, 50)
    end

    it "has a unique market hash name per entry" do
      names = entries.map { |entry| entry.fetch("market_hash_name") }

      expect(names.uniq.size).to eq(names.size)
    end

    it "has every required field on every entry" do
      entries.each do |entry|
        aggregate_failures("entry #{entry.inspect}") do
          expect(entry["market_hash_name"]).to be_present
          expect(entry["rarity"]).to be_present
          expect(entry["category"]).to be_present
          expect(entry["icon_url"]).to be_present
        end
      end
    end

    it "uses a real Steam CDN icon URL for every entry" do
      entries.each do |entry|
        expect(entry.fetch("icon_url")).to match(
          %r{\Ahttps://community\.akamai\.steamstatic\.com/economy/image/\S+\z}
        )
      end
    end

    it "uses rarity labels understood by RarityTier for every entry" do
      entries.each do |entry|
        tier = RarityTier.for(
          market_hash_name: entry.fetch("market_hash_name"),
          rarity: entry.fetch("rarity")
        )

        expect(tier).to be_present, "#{entry.fetch("market_hash_name")} has unknown rarity #{entry.fetch("rarity")}"
      end
    end

    it "uses known Steam inventory categories for every entry" do
      entries.each do |entry|
        expect(known_categories).to include(entry.fetch("category"))
      end
    end
  end

  describe ".market_hash_names" do
    it "returns the item names from the pool" do
      names = described_class.market_hash_names

      aggregate_failures do
        expect(names).to include("AK-47 | Redline (Field-Tested)")
        expect(names).to eq(entries.map { |entry| entry.fetch("market_hash_name") })
      end
    end
  end
end
