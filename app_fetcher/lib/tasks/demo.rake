namespace :demo do
  desc "Create the curated demo item pool and enqueue price updates"
  task seed_items: :environment do
    Demo::ItemPool.entries.each do |entry|
      attrs = ItemParser.parse(
        entry.fetch("market_hash_name"),
        marketable: true,
        tradable: true,
        rarity: entry["rarity"],
        category: entry["category"]
      )

      item = Item.find_or_initialize_by(market_hash_name: attrs[:market_hash_name])

      if item.new_record?
        item.metadata = attrs[:metadata]
        item.save!
      end

      PriceUpdateWorker.perform_async(item.id)
    end
  end
end
