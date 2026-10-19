require "rails_helper"

RSpec.describe ItemParser do
  describe ".parse" do
    it "splits weapon type, item name, and condition out of a plain name" do
      result = described_class.parse("AK-47 | Redline (Field-Tested)")

      aggregate_failures do
        expect(result[:market_hash_name]).to eq("AK-47 | Redline (Field-Tested)")
        expect(result[:metadata][:weapon_type]).to eq("AK-47")
        expect(result[:metadata][:item_name]).to eq("Redline")
        expect(result[:metadata][:condition]).to eq("Field-Tested")
        expect(result[:metadata][:stattrak]).to eq(false)
        expect(result[:metadata][:souvenir]).to eq(false)
      end
    end

    it "detects a StatTrak name and strips the marker from the item name" do
      result = described_class.parse("StatTrak™ AK-47 | Redline (Field-Tested)")

      expect(result[:metadata][:stattrak]).to eq(true)
      expect(result[:metadata][:item_name]).to eq("Redline")
    end

    it "detects a Souvenir name and strips the marker from the weapon type" do
      result = described_class.parse("Souvenir AWP | Dragon Lore (Factory New)")

      expect(result[:metadata][:souvenir]).to eq(true)
      expect(result[:metadata][:weapon_type]).to eq("AWP")
    end

    it "leaves weapon_type nil and treats the whole name as item_name when there is no ' | ' separator" do
      result = described_class.parse("Fracture Case")

      expect(result[:metadata][:weapon_type]).to be_nil
      expect(result[:metadata][:item_name]).to eq("Fracture Case")
    end

    it "leaves condition nil when the name has no trailing (...)" do
      result = described_class.parse("AK-47 | Redline")

      expect(result[:metadata][:condition]).to be_nil
    end

    it "extracts condition from a trailing (...) even without a ' | ' separator" do
      result = described_class.parse("Fracture Case (Factory New)")

      aggregate_failures do
        expect(result[:metadata][:weapon_type]).to be_nil
        expect(result[:metadata][:item_name]).to eq("Fracture Case")
        expect(result[:metadata][:condition]).to eq("Factory New")
      end
    end

    it "includes a given icon_url in the metadata" do
      result = described_class.parse("AK-47 | Redline (Field-Tested)", icon_url: "https://example.com/icon.png")

      expect(result[:metadata][:icon_url]).to eq("https://example.com/icon.png")
    end

    it "defaults icon_url to nil when not given" do
      result = described_class.parse("AK-47 | Redline (Field-Tested)")

      expect(result[:metadata][:icon_url]).to be_nil
    end

    it "includes given marketable/tradable/rarity/category values in the metadata" do
      result = described_class.parse(
        "AK-47 | Redline (Field-Tested)",
        marketable: true,
        tradable: false,
        rarity: "Classified",
        category: "Rifle"
      )

      aggregate_failures do
        expect(result[:metadata][:marketable]).to eq(true)
        expect(result[:metadata][:tradable]).to eq(false)
        expect(result[:metadata][:rarity]).to eq("Classified")
        expect(result[:metadata][:category]).to eq("Rifle")
      end
    end

    it "defaults marketable/tradable to false and rarity/category to nil when not given" do
      result = described_class.parse("AK-47 | Redline (Field-Tested)")

      aggregate_failures do
        expect(result[:metadata][:marketable]).to eq(false)
        expect(result[:metadata][:tradable]).to eq(false)
        expect(result[:metadata][:rarity]).to be_nil
        expect(result[:metadata][:category]).to be_nil
      end
    end
  end

  describe ".parse_collection" do
    it "parses every name in the collection" do
      result = described_class.parse_collection([ "AK-47 | Redline (Field-Tested)", "Fracture Case" ])

      expect(result.map { |dto| dto[:market_hash_name] }).to eq([ "AK-47 | Redline (Field-Tested)", "Fracture Case" ])
    end

    it "returns an empty array for an empty collection" do
      expect(described_class.parse_collection([])).to eq([])
    end
  end
end
