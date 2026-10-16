# typed: strict

class UserInventorySyncService
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(ServiceResult[T::Array[Item]]) }
    def call(steam_id)
      response = Steam::Client.new.fetch_user_inventory(steam_id)
      unless response.success?
        return ServiceResult[T::Array[Item]].new(
          status: ServiceResult::Status::Failed, data: nil, error: response.error
        )
      end

      data = T.must(response.data)
      Rails.logger.warn("[UserInventorySyncService] steam_id=#{steam_id} inventory truncated (more_items)") if data.more_items

      names = data.market_hash_names
      known_items = ItemPriceCache.fetch_for(names)
      missing_names = names - known_items.keys
      icon_by_name = data.icon_urls_by_name
      item_attributes_by_name = data.item_attributes_by_name
      missing_attrs = missing_names.map do |name|
        attrs = item_attributes_by_name[name] || { marketable: false, tradable: false, rarity: nil, category: nil }
        ItemParser.parse(
          name,
          icon_url: icon_by_name[name],
          marketable: attrs[:marketable],
          tradable: attrs[:tradable],
          rarity: attrs[:rarity],
          category: attrs[:category]
        )
      end

      Item.upsert_all(missing_attrs, unique_by: :market_hash_name) if missing_attrs.any?
      backfilled = missing_attrs.empty? ? [] : Item.where(market_hash_name: missing_attrs.map { |attrs| attrs[:market_hash_name] }).to_a
      all_items = known_items.values + backfilled

      UserInventory.sync!(steam_id, all_items.map(&:id))
      UserInventoryCache.invalidate(steam_id)

      ServiceResult[T::Array[Item]].new(status: ServiceResult::Status::Ok, data: all_items, error: nil)
    end
  end
end
