require "rails_helper"

RSpec.describe Appliers::FilterApplier do
  describe ".call" do
    it "reduces every enum value's #apply over the scope with AND semantics" do
      match = create(:item, metadata: { category: "Rifles", rarity: "Classified" })
      wrong_category = create(:item, metadata: { category: "Knives", rarity: "Classified" })
      wrong_rarity = create(:item, metadata: { category: "Rifles", rarity: "Covert" })
      scope = Item.where(id: [ match.id, wrong_category.id, wrong_rarity.id ])

      result = described_class.call(
        scope,
        ActionController::Parameters.new(category: [ "Rifles" ], rarity: [ "Classified" ]),
        enum_class: Options::ItemFilterOption
      )

      expect(result.to_a).to eq([ match ])
    end

    it "returns the scope unchanged when no params are given" do
      item = create(:item)
      scope = Item.where(id: [ item.id ])

      result = described_class.call(scope, ActionController::Parameters.new, enum_class: Options::ItemFilterOption)

      expect(result.to_a).to eq([ item ])
    end
  end
end
