# typed: strict

require "net/http"
require "uri"
require "json"

module Steam
  class InventoryFetcher
    extend T::Sig

    ItemMetadata = T.type_alias do
      { weapon_type: T.nilable(String), item_name: T.nilable(String), condition: T.nilable(String), stattrak: T.nilable(T::Boolean) }
    end
    InventoryItem = T.type_alias do
      { market_hash_name: String, metadata: ItemMetadata, current_price_cents: T.nilable(Integer) }
    end
    InventoryData = T.type_alias { { items_count: Integer, items: T::Array[InventoryItem] } }

    sig { params(steam_id: String).returns(T.nilable(InventoryData)) }
    def self.call(steam_id)
      base_url = ENV.fetch("APP_FETCHER_URL", "http://app_fetcher:3001")
      uri = URI("#{base_url}/api/v1/inventories/#{steam_id}")

      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(T.must(response.body))
      items = T.let(data["items"] || [], T::Array[T::Hash[String, T.untyped]])

      {
        items_count: data["items_count"].to_i,
        items: items.map { |item| build_item(item) }
      }
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
      nil
    end

    sig { params(raw_item: T::Hash[String, T.untyped]).returns(InventoryItem) }
    def self.build_item(raw_item)
      metadata = raw_item["metadata"] || {}

      {
        market_hash_name: raw_item["market_hash_name"].to_s,
        metadata: {
          weapon_type: metadata["weapon_type"],
          item_name: metadata["item_name"],
          condition: metadata["condition"],
          stattrak: metadata["stattrak"]
        },
        current_price_cents: raw_item["current_price_cents"]
      }
    end
    private_class_method :build_item
  end
end
