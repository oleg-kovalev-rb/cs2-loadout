require "rails_helper"

RSpec.describe Steam::Response::Data::InventoryData do
  describe ".from_hash" do
    subject(:data) { described_class.from_hash(hash) }

    context "when the raw hash signals more_items" do
      let(:hash) { { "assets" => [], "descriptions" => [], "more_items" => 1 } }

      it "sets more_items to true" do
        expect(data.more_items).to be(true)
      end
    end

    context "when the raw hash has no more_items key" do
      let(:hash) { { "assets" => [], "descriptions" => [] } }

      it "sets more_items to false" do
        expect(data.more_items).to be(false)
      end
    end

    context "when the raw hash explicitly has a falsy more_items" do
      let(:hash) { { "assets" => [], "descriptions" => [], "more_items" => false } }

      it "sets more_items to false" do
        expect(data.more_items).to be(false)
      end
    end
  end

  describe "#icon_urls_by_name" do
    subject(:icon_urls_by_name) { described_class.from_hash(hash).icon_urls_by_name }

    context "when descriptions have both an icon_url and a market_hash_name" do
      let(:hash) do
        {
          "assets" => [],
          "descriptions" => [
            { "market_hash_name" => "AK-47 | Redline (Field-Tested)", "icon_url" => "abc123" },
            { "market_hash_name" => "AWP | Asiimov (Battle-Scarred)", "icon_url" => "def456" }
          ]
        }
      end

      it "maps each name to its full Steam economy-image URL" do
        expect(icon_urls_by_name).to eq(
          "AK-47 | Redline (Field-Tested)" => "https://community.akamai.steamstatic.com/economy/image/abc123",
          "AWP | Asiimov (Battle-Scarred)" => "https://community.akamai.steamstatic.com/economy/image/def456"
        )
      end
    end

    context "when a description has no icon_url" do
      let(:hash) do
        { "assets" => [], "descriptions" => [ { "market_hash_name" => "AK-47 | Redline (Field-Tested)" } ] }
      end

      it "maps the name to nil" do
        expect(icon_urls_by_name).to eq("AK-47 | Redline (Field-Tested)" => nil)
      end
    end

    context "when a description has no market_hash_name" do
      let(:hash) { { "assets" => [], "descriptions" => [ { "icon_url" => "abc123" } ] } }

      it "is skipped" do
        expect(icon_urls_by_name).to eq({})
      end
    end
  end

  describe "#item_attributes_by_name" do
    subject(:item_attributes_by_name) { described_class.from_hash(hash).item_attributes_by_name }

    context "when a description has marketable, tradable, and a Rarity tag" do
      let(:hash) do
        {
          "assets" => [],
          "descriptions" => [
            {
              "market_hash_name" => "AK-47 | Redline (Field-Tested)",
              "marketable" => 1,
              "tradable" => 0,
              "tags" => [
                { "category" => "Type", "localized_tag_name" => "Rifle" },
                { "category" => "Rarity", "localized_tag_name" => "Classified" }
              ]
            }
          ]
        }
      end

      it "resolves marketable/tradable as booleans, rarity from the Rarity-category tag, and category from the Type-category tag" do
        expect(item_attributes_by_name).to eq(
          "AK-47 | Redline (Field-Tested)" => {
            marketable: true, tradable: false, rarity: "Classified", category: "Rifle"
          }
        )
      end
    end

    context "when marketable/tradable are both 0 and there is no Rarity tag" do
      let(:hash) do
        {
          "assets" => [],
          "descriptions" => [
            {
              "market_hash_name" => "AWP | Asiimov (Battle-Scarred)",
              "marketable" => 0,
              "tradable" => 0,
              "tags" => [ { "category" => "Type", "localized_tag_name" => "Sniper Rifle" } ]
            }
          ]
        }
      end

      it "resolves both flags to false (not truthy-on-integer-0), rarity to nil, and category from the Type tag" do
        expect(item_attributes_by_name).to eq(
          "AWP | Asiimov (Battle-Scarred)" => {
            marketable: false, tradable: false, rarity: nil, category: "Sniper Rifle"
          }
        )
      end
    end

    context "when a description has no tags key at all" do
      let(:hash) do
        {
          "assets" => [],
          "descriptions" => [
            { "market_hash_name" => "Fracture Case", "marketable" => 1, "tradable" => 1 }
          ]
        }
      end

      it "treats it the same as an empty tags array, resolving rarity and category to nil" do
        expect(item_attributes_by_name).to eq(
          "Fracture Case" => { marketable: true, tradable: true, rarity: nil, category: nil }
        )
      end
    end

    context "when the Rarity tag is not the first element of tags" do
      let(:hash) do
        {
          "assets" => [],
          "descriptions" => [
            {
              "market_hash_name" => "Sticker | Scorch Loop",
              "marketable" => 1,
              "tradable" => 1,
              "tags" => [
                { "category" => "Type", "localized_tag_name" => "Sticker" },
                { "category" => "Quality", "localized_tag_name" => "Normal" },
                { "category" => "Rarity", "localized_tag_name" => "High Grade" },
                { "category" => "StickerCapsule", "localized_tag_name" => "Elemental Craft Sticker Pack" }
              ]
            }
          ]
        }
      end

      it "still finds the Rarity tag regardless of its position" do
        expect(item_attributes_by_name).to eq(
          "Sticker | Scorch Loop" => { marketable: true, tradable: true, rarity: "High Grade", category: "Sticker" }
        )
      end
    end

    context "when the Type tag is not the first element of tags" do
      let(:hash) do
        {
          "assets" => [],
          "descriptions" => [
            {
              "market_hash_name" => "Karambit | Fade (Factory New)",
              "marketable" => 1,
              "tradable" => 1,
              "tags" => [
                { "category" => "Rarity", "localized_tag_name" => "Covert" },
                { "category" => "Quality", "localized_tag_name" => "Normal" },
                { "category" => "Type", "localized_tag_name" => "Knife" }
              ]
            }
          ]
        }
      end

      it "still finds the Type tag regardless of its position" do
        expect(item_attributes_by_name).to eq(
          "Karambit | Fade (Factory New)" => { marketable: true, tradable: true, rarity: "Covert", category: "Knife" }
        )
      end
    end

    context "when a description has no market_hash_name" do
      let(:hash) do
        { "assets" => [], "descriptions" => [ { "marketable" => 1, "tradable" => 1 } ] }
      end

      it "is skipped" do
        expect(item_attributes_by_name).to eq({})
      end
    end
  end
end
