require "rails_helper"

RSpec.describe ItemMetadataSerializer do
  it "exposes exactly the 7 public metadata keys" do
    item = Item.new(
      market_hash_name: "AK-47 | Redline (Field-Tested)",
      metadata: {
        marketable: true, tradable: true, souvenir: false, weapon_type: "AK-47", item_name: "Redline",
        category: "Rifles", condition: "Field-Tested", stattrak: false,
        icon_url: "https://example.com/icon.png", rarity: "Classified"
      }
    )

    expect(described_class.call(item)).to eq(
      weapon_type: "AK-47",
      item_name: "Redline",
      category: "Rifles",
      condition: "Field-Tested",
      stattrak: false,
      icon_url: "https://example.com/icon.png",
      rarity: "Classified"
    )
  end
end
