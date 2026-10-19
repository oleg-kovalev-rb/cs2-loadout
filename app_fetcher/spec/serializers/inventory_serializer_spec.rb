require "rails_helper"

RSpec.describe InventorySerializer do
  it "shapes the item count and per-item inventory fields" do
    items = [
      Item.new(
        market_hash_name: "AK-47 | Redline (Field-Tested)",
        price_unavailable: false,
        metadata: { item_name: "Redline" }
      ),
      Item.new(
        market_hash_name: "AWP | Asiimov (Field-Tested)",
        price_unavailable: true,
        metadata: { item_name: "Asiimov" }
      )
    ]

    expect(described_class.call(items)).to eq(
      items_count: 2,
      items: [
        {
          market_hash_name: "AK-47 | Redline (Field-Tested)",
          price_unavailable: false,
          metadata: { "item_name" => "Redline" }
        },
        {
          market_hash_name: "AWP | Asiimov (Field-Tested)",
          price_unavailable: true,
          metadata: { "item_name" => "Asiimov" }
        }
      ]
    )
  end

  it "returns a zero count and empty items for an empty inventory" do
    expect(described_class.call([])).to eq(items_count: 0, items: [])
  end
end
