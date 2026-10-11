require "rails_helper"

RSpec.describe Appliers::Pagination do
  describe "#page / #per_page" do
    it "defaults to page 1, per_page 25 when absent" do
      pagination = described_class.new(nil, nil)

      expect(pagination.page).to eq(1)
      expect(pagination.per_page).to eq(25)
    end

    it "clamps page 0, -1, and non-numeric to 1" do
      [ "0", "-1", "abc" ].each do |raw|
        expect(described_class.new(raw, nil).page).to eq(1)
      end
    end

    it "clamps an oversized per_page to 100" do
      expect(described_class.new(nil, "9999").per_page).to eq(100)
    end

    it "clamps a non-positive per_page to 1" do
      expect(described_class.new(nil, "0").per_page).to eq(1)
    end
  end

  describe "#offset" do
    it "computes the offset from page and per_page" do
      expect(described_class.new("3", "10").offset).to eq(20)
    end
  end

  describe "#total_pages" do
    it "returns 0 when total_count is 0" do
      expect(described_class.new(nil, nil).total_pages(0)).to eq(0)
    end

    it "rounds up a partial page" do
      expect(described_class.new(nil, "10").total_pages(25)).to eq(3)
    end
  end
end
