require "rails_helper"

RSpec.describe InventoryDetailCache do
  let(:steam_id_a) { "76561198000000001" }
  let(:steam_id_b) { "76561198000000002" }
  let(:params_a) { ActionController::Parameters.new(range: "7d", items_sort: "price_desc") }
  let(:params_b) { ActionController::Parameters.new(range: "30d", items_sort: "name_asc") }
  let(:payload) { { steam_id: steam_id_a, portfolio: {} } }

  describe ".read / .write" do
    it "round-trips a written value for the same steam_id and params" do
      described_class.write(steam_id_a, params_a, payload)

      expect(described_class.read(steam_id_a, params_a)).to eq(payload)
    end

    it "returns nil for a steam_id/params combination that was never written" do
      expect(described_class.read(steam_id_a, params_a)).to be_nil
    end

    it "does not collide between different steam_ids with identical params" do
      described_class.write(steam_id_a, params_a, payload)

      expect(described_class.read(steam_id_b, params_a)).to be_nil
    end

    it "does not collide between different params for the same steam_id" do
      described_class.write(steam_id_a, params_a, payload)

      expect(described_class.read(steam_id_a, params_b)).to be_nil
    end
  end

  describe "TTL" do
    it "expires a written value after the cache's TTL has passed" do
      described_class.write(steam_id_a, params_a, payload)

      travel_to((InventoryDetailCache::TTL + 1.second).from_now) do
        expect(described_class.read(steam_id_a, params_a)).to be_nil
      end
    end

    it "still returns the value just before the TTL elapses" do
      described_class.write(steam_id_a, params_a, payload)

      travel_to((InventoryDetailCache::TTL - 1.second).from_now) do
        expect(described_class.read(steam_id_a, params_a)).to eq(payload)
      end
    end
  end
end
