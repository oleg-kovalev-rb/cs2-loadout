require "rails_helper"

RSpec.describe UserInventoryCache do
  let(:steam_id) { "76561198000000001" }

  describe ".read" do
    it "returns nil when nothing is cached for this steam_id" do
      expect(described_class.read(steam_id)).to be_nil
    end

    it "returns the names written for this steam_id" do
      described_class.write(steam_id, [ "AK-47 | Redline (Field-Tested)" ])

      expect(described_class.read(steam_id)).to eq([ "AK-47 | Redline (Field-Tested)" ])
    end
  end

  describe ".write" do
    it "is scoped per steam_id, not shared across users" do
      described_class.write(steam_id, [ "A" ])
      described_class.write("76561198000000002", [ "B" ])

      aggregate_failures do
        expect(described_class.read(steam_id)).to eq([ "A" ])
        expect(described_class.read("76561198000000002")).to eq([ "B" ])
      end
    end
  end
end
