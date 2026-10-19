require "rails_helper"

RSpec.describe PriceWarmupService do
  subject(:call) { described_class.call(items) }

  let(:unpriced_items) { [ build_item(id: 1), build_item(id: 2), build_item(id: 3) ] }
  let(:priced_item) { build_item(id: 4, current_price_cents: 1000) }
  let(:items) { unpriced_items + [ priced_item ] }

  def build_item(id:, current_price_cents: nil)
    Item.new(id: id, market_hash_name: "item-#{id}", current_price_cents: current_price_cents)
  end

  it "enqueues only unpriced items and returns Success with their ids" do
    result = call

    aggregate_failures do
      expect(result.success?).to be(true)
      expect(result.data).to contain_exactly(1, 2, 3)
      expect(PriceUpdateWorker.jobs.map { |job| job["args"].first }).to contain_exactly(1, 2, 3)
    end
  end

  it "returns Success with an empty array when nothing is eligible" do
    result = described_class.call([ priced_item ])

    aggregate_failures do
      expect(result.success?).to be(true)
      expect(result.data).to eq([])
      expect(PriceUpdateWorker.jobs).to be_empty
    end
  end

  it "caps a single call at 20 enqueues" do
    result = described_class.call((1..21).map { |id| build_item(id: id) })

    aggregate_failures do
      expect(result.data.size).to eq(20)
      expect(PriceUpdateWorker.jobs.size).to eq(20)
    end
  end

  it "deduplicates repeated calls within the TTL" do
    first = described_class.call(items)
    second = described_class.call(items)

    aggregate_failures do
      expect(first.data).to contain_exactly(1, 2, 3)
      expect(second.data).to eq([])
      expect(PriceUpdateWorker.jobs.size).to eq(3)
    end
  end
end
