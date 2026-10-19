require "rails_helper"

RSpec.describe RarityBreakdownSerializer do
  it "builds all 7 tiers with percentages against the classified count" do
    breakdown = described_class.call({ RarityTier::Covert => 1, RarityTier::Classified => 3 })

    covert = breakdown.find { |entry| entry[:tier] == "covert" }
    classified = breakdown.find { |entry| entry[:tier] == "classified" }
    gold = breakdown.find { |entry| entry[:tier] == "gold" }

    aggregate_failures do
      expect(breakdown.size).to eq(7)
      expect(covert).to eq(tier: "covert", count: 1, percent: 25.0)
      expect(classified).to eq(tier: "classified", count: 3, percent: 75.0)
      expect(gold).to eq(tier: "gold", count: 0, percent: 0.0)
    end
  end

  it "returns all-zero percentages when nothing is classified" do
    breakdown = described_class.call({})

    expect(breakdown.map { |entry| entry[:percent] }).to all(eq(0.0))
  end
end
