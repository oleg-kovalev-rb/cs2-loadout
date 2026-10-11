require "rails_helper"

RSpec.describe ItemCatalogCache do
  let(:filters_a) do
    { page: 1, per_page: 24, search: nil, category: [ "Rifles" ], rarity: [], stattrak: false, sort: "change_24h_desc" }
  end
  let(:filters_b) do
    { page: 2, per_page: 24, search: nil, category: [ "Knives" ], rarity: [], stattrak: false, sort: "price_desc" }
  end
  let(:payload) { { meta: { page: 1 }, items: [] } }

  describe ".read / .write" do
    it "round-trips a written value for the same normalized filters" do
      described_class.write(filters_a, payload)

      expect(described_class.read(filters_a)).to eq(payload)
    end

    it "returns nil for filters that were never written" do
      expect(described_class.read(filters_a)).to be_nil
    end

    it "does not return filters_a's value when reading under different filters (no key collision)" do
      described_class.write(filters_a, payload)

      expect(described_class.read(filters_b)).to be_nil
    end
  end

  describe "TTL" do
    it "expires a written value after the cache's TTL has passed" do
      described_class.write(filters_a, payload)

      travel_to((ItemCatalogCache::TTL + 1.second).from_now) do
        expect(described_class.read(filters_a)).to be_nil
      end
    end

    it "still returns the value just before the TTL elapses" do
      described_class.write(filters_a, payload)

      travel_to((ItemCatalogCache::TTL - 1.second).from_now) do
        expect(described_class.read(filters_a)).to eq(payload)
      end
    end
  end
end
