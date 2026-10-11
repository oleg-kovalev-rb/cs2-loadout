# typed: strict

class Steam::Response::Data::InventoryData < T::Struct
  extend T::Sig
  extend Steam::Response::DataClassMethods

  ICON_CDN_BASE_URL = T.let("https://community.akamai.steamstatic.com/economy/image/".freeze, String)
  RARITY_TAG_CATEGORY = T.let("Rarity".freeze, String)

  ItemAttributes = T.type_alias do
    { marketable: T::Boolean, tradable: T::Boolean, rarity: T.nilable(String) }
  end

  const :assets, T::Array[T::Hash[String, T.untyped]]
  const :descriptions, T::Array[T::Hash[String, T.untyped]]
  const :more_items, T::Boolean

  sig { override.params(hash: T::Hash[String, T.untyped]).returns(Steam::Response::Data::InventoryData) }
  def self.from_hash(hash)
    Steam::Response::Data::InventoryData.new(
      assets: hash["assets"] || [],
      descriptions: hash["descriptions"] || [],
      more_items: !!hash["more_items"]
    )
  end

  sig { returns(T::Array[String]) }
  def market_hash_names
    descriptions.map { |desc| desc["market_hash_name"] }.compact.uniq
  end

  sig { returns(T::Hash[String, T.nilable(String)]) }
  def icon_urls_by_name
    descriptions.each_with_object({}) do |desc, acc|
      name = desc["market_hash_name"]
      next unless name

      icon = desc["icon_url"]
      acc[name] = icon.nil? ? nil : "#{ICON_CDN_BASE_URL}#{icon}"
    end
  end

  sig { returns(T::Hash[String, ItemAttributes]) }
  def item_attributes_by_name
    descriptions.each_with_object({}) do |desc, acc|
      name = desc["market_hash_name"]
      next unless name

      acc[name] = {
        marketable: desc["marketable"] == 1,
        tradable: desc["tradable"] == 1,
        rarity: rarity_tag(desc)
      }
    end
  end

  private

  sig { params(desc: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
  def rarity_tag(desc)
    tags = desc["tags"] || []
    tags.find { |tag| tag["category"] == RARITY_TAG_CATEGORY }&.dig("localized_tag_name")
  end
end
