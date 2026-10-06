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
end
