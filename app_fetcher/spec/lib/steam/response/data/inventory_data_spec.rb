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
end
