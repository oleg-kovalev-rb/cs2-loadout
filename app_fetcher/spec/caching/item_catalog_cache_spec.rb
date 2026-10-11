require "rails_helper"

RSpec.describe ItemCatalogCache do
  let(:params_a) { ActionController::Parameters.new(page: "1", category: [ "Rifles" ], sort: "change_24h_desc") }
  let(:params_b) { ActionController::Parameters.new(page: "2", category: [ "Knives" ], sort: "price_desc") }
  let(:payload) { { meta: { page: 1 }, items: [] } }

  describe ".read / .write" do
    it "round-trips a written value for the same params" do
      described_class.write(params_a, payload)

      expect(described_class.read(params_a)).to eq(payload)
    end

    it "returns nil for params that were never written" do
      expect(described_class.read(params_a)).to be_nil
    end

    it "does not return params_a's value when reading under different params (no key collision)" do
      described_class.write(params_a, payload)

      expect(described_class.read(params_b)).to be_nil
    end

    it "treats equivalent params the same regardless of array ordering" do
      described_class.write(ActionController::Parameters.new(category: [ "Rifles", "Knives" ]), payload)

      expect(described_class.read(ActionController::Parameters.new(category: [ "Knives", "Rifles" ]))).to eq(payload)
    end
  end

  describe "TTL" do
    it "expires a written value after the cache's TTL has passed" do
      described_class.write(params_a, payload)

      travel_to((ItemCatalogCache::TTL + 1.second).from_now) do
        expect(described_class.read(params_a)).to be_nil
      end
    end

    it "still returns the value just before the TTL elapses" do
      described_class.write(params_a, payload)

      travel_to((ItemCatalogCache::TTL - 1.second).from_now) do
        expect(described_class.read(params_a)).to eq(payload)
      end
    end
  end
end
