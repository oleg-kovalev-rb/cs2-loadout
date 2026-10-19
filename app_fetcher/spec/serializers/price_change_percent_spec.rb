require "rails_helper"

RSpec.describe PriceChangePercent do
  it "computes the percent against the pre-change base" do
    expect(described_class.call(current_cents: 4218, change_cents: 130)).to be_within(0.01).of(3.18)
  end

  it "returns 0.0 for a nil current price" do
    expect(described_class.call(current_cents: nil, change_cents: 130)).to eq(0.0)
  end

  it "returns 0.0 when the pre-change base is zero" do
    expect(described_class.call(current_cents: 500, change_cents: 500)).to eq(0.0)
  end

  it "handles negative changes" do
    expect(described_class.call(current_cents: 900, change_cents: -50)).to be_within(0.01).of(-5.26)
  end
end
