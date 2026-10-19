require "rails_helper"

RSpec.describe ItemListQuery do
  describe ".call" do
    it "returns only marketable items, defaulted sort" do
      gaining = create(:item, current_price_cents: 1000, change_24h_cents: 100)
      losing = create(:item, current_price_cents: 900, change_24h_cents: -50)
      non_marketable = create(:item, metadata: { marketable: false })

      page = described_class.call(ActionController::Parameters.new)

      names = page.items.map(&:market_hash_name)
      expect(names).to include(gaining.market_hash_name, losing.market_hash_name)
      expect(names).not_to include(non_marketable.market_hash_name)
      expect(names.index(gaining.market_hash_name)).to be < names.index(losing.market_hash_name)
    end

    it "applies filters" do
      rifle = create(:item, metadata: { marketable: true, category: "Rifles" })
      knife = create(:item, metadata: { marketable: true, category: "Knives" })

      page = described_class.call(ActionController::Parameters.new(category: [ "Rifles" ]))

      names = page.items.map(&:market_hash_name)
      expect(names).to include(rifle.market_hash_name)
      expect(names).not_to include(knife.market_hash_name)
    end

    it "applies pagination" do
      create_list(:item, 3, metadata: { marketable: true })

      page = described_class.call(ActionController::Parameters.new(page: "1", per_page: "1"))

      expect(page.items.size).to eq(1)
      expect(page.pagination.page).to eq(1)
      expect(page.pagination.per_page).to eq(1)
    end

    it "computes total_count/price_change_stats scoped to the current filters" do
      create(:item, change_24h_cents: 50, metadata: { marketable: true, category: "Rifles" })
      create(:item, change_24h_cents: -50, metadata: { marketable: true, category: "Rifles" })
      create(:item, change_24h_cents: 50, metadata: { marketable: true, category: "Knives" })

      page = described_class.call(ActionController::Parameters.new(category: [ "Rifles" ]))

      expect(page.total_count).to eq(2)
      expect(page.price_change_stats.gaining_count).to eq(1)
      expect(page.price_change_stats.losing_count).to eq(1)
    end

    it "fetches trend data for the returned page's items" do
      item = create(:item, metadata: { marketable: true })
      create(:price_log, item: item, lowest_price_cents: 4000, created_at: 2.days.ago)

      page = described_class.call(ActionController::Parameters.new)

      expect(page.trends[item.market_hash_name]).not_to be_nil
    end

    it "computes last_synced_at as the max updated_at among marketable items" do
      create(:item, metadata: { marketable: true })

      page = described_class.call(ActionController::Parameters.new)

      expect(page.last_synced_at&.iso8601).to eq(Item.marketable.maximum(:updated_at).iso8601)
    end

    it "propagates Api::Public::UnsupportedParamError for an invalid sort, without rescuing it" do
      expect {
        described_class.call(ActionController::Parameters.new(sort: "bogus"))
      }.to raise_error(Api::Public::UnsupportedParamError, "Unsupported sort: bogus")
    end
  end
end
