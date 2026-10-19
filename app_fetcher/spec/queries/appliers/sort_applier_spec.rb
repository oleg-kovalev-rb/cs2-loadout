require "rails_helper"

RSpec.describe Appliers::SortApplier do
  describe ".call" do
    let!(:cheap) { create(:item, current_price_cents: 100) }
    let!(:expensive) { create(:item, current_price_cents: 900) }
    let(:scope) { Item.where(id: [ cheap.id, expensive.id ]) }

    it "applies the default ordering when the param is absent" do
      result = described_class.call(
        scope,
        ActionController::Parameters.new,
        enum_class: Options::ItemSortOption,
        default: Options::ItemSortOption::PriceDesc
      )

      expect(result.to_a).to eq([ expensive, cheap ])
    end

    it "applies the ordering for a recognized value" do
      result = described_class.call(
        scope,
        ActionController::Parameters.new(sort: "price_asc"),
        enum_class: Options::ItemSortOption,
        default: Options::ItemSortOption::PriceDesc
      )

      expect(result.to_a).to eq([ cheap, expensive ])
    end

    it "returns a relation" do
      result = described_class.call(
        scope,
        ActionController::Parameters.new,
        enum_class: Options::ItemSortOption,
        default: Options::ItemSortOption::PriceDesc
      )

      expect(result).to be_a(ActiveRecord::Relation)
    end

    it "raises Api::Public::UnsupportedParamError for an unrecognized value" do
      expect {
        described_class.call(
          scope,
          ActionController::Parameters.new(sort: "bogus"),
          enum_class: Options::ItemSortOption,
          default: Options::ItemSortOption::PriceDesc
        )
      }.to raise_error(Api::Public::UnsupportedParamError, "Unsupported sort: bogus")
    end

    it "uses the given param_name in the error message" do
      expect {
        described_class.call(
          scope,
          ActionController::Parameters.new(items_sort: "bogus"),
          enum_class: Options::ItemSortOption,
          default: Options::ItemSortOption::PriceDesc,
          param_name: "items_sort"
        )
      }.to raise_error(Api::Public::UnsupportedParamError, "Unsupported items_sort: bogus")
    end
  end
end
