# typed: strict

class UserInventorySyncService
  extend T::Sig

  class Result < T::Struct
    const :success, T::Boolean
    const :error, T.nilable(String)
    const :items, T.nilable(T::Array[Item])
  end

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(UserInventorySyncService::Result) }
    def call(steam_id)
      response = Steam::Client.new.fetch_user_inventory(steam_id)
      return Result.new(success: false, error: response.error, items: nil) unless response.success?

      Rails.logger.warn("[UserInventorySyncService] steam_id=#{steam_id} inventory truncated (more_items)") if response.data.more_items

      names = response.data.market_hash_names
      known_items = ItemPriceCache.fetch_for(names)
      missing_names = names - known_items.keys
      missing_attrs = missing_names.map { |name| Steam::ItemParser.parse(name) }

      Item.upsert_all(missing_attrs, unique_by: :market_hash_name) if missing_attrs.any?
      backfilled = missing_attrs.empty? ? [] : Item.where(market_hash_name: missing_attrs.map { |attrs| attrs[:market_hash_name] }).to_a
      all_items = known_items.values + backfilled

      UserInventory.sync!(steam_id, all_items.map(&:id))
      UserInventoryCache.invalidate(steam_id)

      Result.new(success: true, error: nil, items: all_items)
    end
  end
end
