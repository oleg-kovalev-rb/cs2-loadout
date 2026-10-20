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

    it "raises the given error_class for an unrecognized value" do
      expect {
        described_class.call(
          scope,
          ActionController::Parameters.new(sort: "bogus"),
          enum_class: Options::ItemSortOption,
          default: Options::ItemSortOption::PriceDesc,
          error_class: Api::V1::UnsupportedParamError
        )
      }.to raise_error(Api::V1::UnsupportedParamError, "Unsupported sort: bogus")
    end

    it "uses the given param_name in the error message" do
      expect {
        described_class.call(
          scope,
          ActionController::Parameters.new(ordering: "bogus"),
          enum_class: Options::ItemSortOption,
          default: Options::ItemSortOption::PriceDesc,
          param_name: "ordering"
        )
      }.to raise_error(Api::Public::UnsupportedParamError, "Unsupported ordering: bogus")
    end
  end
end
