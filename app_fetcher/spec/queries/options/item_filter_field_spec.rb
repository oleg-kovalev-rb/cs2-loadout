require "rails_helper"

RSpec.describe Options::ItemFilterField do
  describe "#apply" do
    describe "Category" do
      it "filters to matching categories when present" do
        rifle = create(:item, metadata: { category: "Rifles" })
        knife = create(:item, metadata: { category: "Knives" })
        scope = Item.where(id: [ rifle.id, knife.id ])

        result = described_class::Category.apply(scope, ActionController::Parameters.new(category: [ "Rifles" ]))

        expect(result.to_a).to eq([ rifle ])
      end

      it "is a no-op when absent" do
        rifle = create(:item, metadata: { category: "Rifles" })
        knife = create(:item, metadata: { category: "Knives" })
        scope = Item.where(id: [ rifle.id, knife.id ])

        result = described_class::Category.apply(scope, ActionController::Parameters.new)

        expect(result.to_a).to contain_exactly(rifle, knife)
      end

      it "matches nothing for an unrecognized category, not an error" do
        rifle = create(:item, metadata: { category: "Rifles" })
        scope = Item.where(id: [ rifle.id ])

        result = described_class::Category.apply(scope, ActionController::Parameters.new(category: [ "NotReal" ]))

        expect(result.to_a).to eq([])
      end
    end

    describe "Rarity" do
      it "filters to matching rarities when present" do
        classified = create(:item, metadata: { rarity: "Classified" })
        covert = create(:item, metadata: { rarity: "Covert" })
        scope = Item.where(id: [ classified.id, covert.id ])

        result = described_class::Rarity.apply(scope, ActionController::Parameters.new(rarity: [ "Classified" ]))

        expect(result.to_a).to eq([ classified ])
      end
    end

    describe "Stattrak" do
      it "filters to stattrak-only items when stattrak=true" do
        stattrak_item = create(:item, metadata: { stattrak: true })
        plain_item = create(:item, metadata: { stattrak: false })
        scope = Item.where(id: [ stattrak_item.id, plain_item.id ])

        result = described_class::Stattrak.apply(scope, ActionController::Parameters.new(stattrak: "true"))

        expect(result.to_a).to eq([ stattrak_item ])
      end

      it "is a no-op when absent or false (not the inverse filter)" do
        stattrak_item = create(:item, metadata: { stattrak: true })
        plain_item = create(:item, metadata: { stattrak: false })
        scope = Item.where(id: [ stattrak_item.id, plain_item.id ])

        expect(described_class::Stattrak.apply(scope, ActionController::Parameters.new).to_a)
          .to contain_exactly(stattrak_item, plain_item)
        expect(described_class::Stattrak.apply(scope, ActionController::Parameters.new(stattrak: "false")).to_a)
          .to contain_exactly(stattrak_item, plain_item)
      end
    end

    describe "Search" do
      it "matches a case-insensitive substring of item_name when present" do
        redline = create(:item, metadata: { item_name: "Redline" })
        asiimov = create(:item, metadata: { item_name: "Asiimov" })
        scope = Item.where(id: [ redline.id, asiimov.id ])

        result = described_class::Search.apply(scope, ActionController::Parameters.new(search: "RED"))

        expect(result.to_a).to eq([ redline ])
      end

      it "is a no-op when absent" do
        redline = create(:item, metadata: { item_name: "Redline" })
        asiimov = create(:item, metadata: { item_name: "Asiimov" })
        scope = Item.where(id: [ redline.id, asiimov.id ])

        result = described_class::Search.apply(scope, ActionController::Parameters.new)

        expect(result.to_a).to contain_exactly(redline, asiimov)
      end
    end
  end
end
