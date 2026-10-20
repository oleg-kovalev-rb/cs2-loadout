require "rails_helper"

RSpec.describe RarityTier do
  describe ".for" do
    it "classifies each raw Steam rarity string to its matching tier" do
      mapping = {
        "Consumer Grade" => RarityTier::Consumer,
        "Industrial Grade" => RarityTier::Industrial,
        "Mil-Spec Grade" => RarityTier::MilSpec,
        "Restricted" => RarityTier::Restricted,
        "Classified" => RarityTier::Classified,
        "Covert" => RarityTier::Covert,
        "Extraordinary" => RarityTier::Gold,
        "Contraband" => RarityTier::Gold
      }

      aggregate_failures do
        mapping.each do |rarity, tier|
          result = described_class.for(market_hash_name: "AK-47 | Redline (Field-Tested)", rarity:)
          expect(result).to eq(tier)
        end
      end
    end

    it "classifies a star-prefixed market_hash_name as gold regardless of its raw rarity" do
      result = described_class.for(market_hash_name: "★ Karambit | Doppler (Factory New)", rarity: "Covert")

      expect(result).to eq(RarityTier::Gold)
    end

    it "classifies a star-prefixed item with no raw rarity at all as gold" do
      result = described_class.for(market_hash_name: "★ Sport Gloves | Pandora's Box (Minimal Wear)", rarity: nil)

      expect(result).to eq(RarityTier::Gold)
    end

    it "returns nil for an unrecognized or missing raw rarity with no star prefix" do
      result = described_class.for(market_hash_name: "AK-47 | Redline (Field-Tested)", rarity: nil)

      expect(result).to be_nil
    end
  end
end
