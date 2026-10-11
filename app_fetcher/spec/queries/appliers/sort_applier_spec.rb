require "rails_helper"

RSpec.describe Appliers::SortApplier do
  describe ".call" do
    it "resolves to the default when the raw value is absent" do
      result = described_class.call(nil, enum_class: Options::ItemSortOption, default: Options::ItemSortOption::ChangeDesc)

      expect(result).to eq(Options::ItemSortOption::ChangeDesc)
    end

    it "resolves to the matching enum member for a recognized value" do
      result = described_class.call("price_desc", enum_class: Options::ItemSortOption, default: Options::ItemSortOption::ChangeDesc)

      expect(result).to eq(Options::ItemSortOption::PriceDesc)
    end

    it "raises Api::Public::UnsupportedParamError for an unrecognized value" do
      expect {
        described_class.call("bogus", enum_class: Options::ItemSortOption, default: Options::ItemSortOption::ChangeDesc)
      }.to raise_error(Api::Public::UnsupportedParamError, "Unsupported sort: bogus")
    end

    it "uses the given param_name in the error message" do
      expect {
        described_class.call(
          "bogus", enum_class: Options::ItemSortOption, default: Options::ItemSortOption::ChangeDesc, param_name: "period"
        )
      }.to raise_error(Api::Public::UnsupportedParamError, "Unsupported period: bogus")
    end
  end
end
