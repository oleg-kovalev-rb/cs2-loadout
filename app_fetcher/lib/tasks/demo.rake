namespace :demo do
  desc "Create the curated demo item pool and enqueue price updates"
  task seed_items: :environment do
    Demo::ItemPool.entries.each do |entry|
      attrs = ItemParser.parse(
        entry.fetch("market_hash_name"),
        icon_url: entry["icon_url"],
        marketable: true,
        tradable: true,
        rarity: entry["rarity"],
        category: entry["category"]
      )

      item = Item.find_or_initialize_by(market_hash_name: attrs[:market_hash_name])

      if item.new_record?
        item.metadata = attrs[:metadata]
        item.save!
      else
        existing_metadata = item.metadata || {}
        parsed_metadata = attrs[:metadata].stringify_keys
        merged_metadata = parsed_metadata.merge(existing_metadata) do |_key, parsed_value, current_value|
          current_value.nil? ? parsed_value : current_value
        end

        item.update!(metadata: merged_metadata) if merged_metadata != existing_metadata
      end

      PriceUpdateWorker.perform_async(item.id)
    end
  end
end
