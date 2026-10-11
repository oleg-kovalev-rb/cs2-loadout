require "rails_helper"

RSpec.describe Options::ItemSortOption do
  describe "#apply" do
    it "ChangeDesc orders by change_24h_cents descending" do
      low = create(:item, change_24h_cents: -50)
      high = create(:item, change_24h_cents: 100)
      scope = Item.where(id: [ low.id, high.id ])

      expect(described_class::ChangeDesc.apply(scope).to_a).to eq([ high, low ])
    end

    it "PriceDesc orders by current_price_cents descending" do
      cheap = create(:item, current_price_cents: 100)
      expensive = create(:item, current_price_cents: 900)
      scope = Item.where(id: [ cheap.id, expensive.id ])

      expect(described_class::PriceDesc.apply(scope).to_a).to eq([ expensive, cheap ])
    end

    it "PriceAsc orders by current_price_cents ascending" do
      cheap = create(:item, current_price_cents: 100)
      expensive = create(:item, current_price_cents: 900)
      scope = Item.where(id: [ cheap.id, expensive.id ])

      expect(described_class::PriceAsc.apply(scope).to_a).to eq([ cheap, expensive ])
    end

    it "NameAsc orders by metadata item_name ascending via raw SQL" do
      bravo = create(:item, metadata: { item_name: "Bravo" })
      alpha = create(:item, metadata: { item_name: "Alpha" })
      scope = Item.where(id: [ bravo.id, alpha.id ])

      expect(described_class::NameAsc.apply(scope).to_a).to eq([ alpha, bravo ])
    end
  end
end
