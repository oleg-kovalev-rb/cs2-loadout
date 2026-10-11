# typed: strict

class ItemParser
  extend T::Sig

  STAT_TRACK_MARKER = "StatTrak™"
  SOUVENIR_MARKER = "Souvenir"
  WEAPON_TYPE_SEPARATOR = " | "

  MARKERS_REGEXP = /StatTrak™\s*|Souvenir\s*/
  CONDITION_EXTRACT_REGEX = T.let(/\((.+?)\)$/.freeze, Regexp)
  CONDITION_CLEANUP_REGEX = T.let(/\s*\(.+?\)$/.freeze, Regexp)

  ItemDto = T.type_alias do
    {
      market_hash_name: String,
      metadata: {
        weapon_type: T.nilable(String),
        item_name: String,
        condition: T.nilable(String),
        stattrak: T::Boolean,
        souvenir: T::Boolean,
        icon_url: T.nilable(String),
        marketable: T::Boolean,
        tradable: T::Boolean,
        rarity: T.nilable(String),
        category: T.nilable(String)
      }
    }
  end

  sig do
    params(
      market_hash_name: String,
      icon_url: T.nilable(String),
      marketable: T::Boolean,
      tradable: T::Boolean,
      rarity: T.nilable(String),
      category: T.nilable(String)
    ).returns(ItemDto)
  end
  def self.parse(market_hash_name, icon_url: nil, marketable: false, tradable: false, rarity: nil, category: nil)
    stattrak = market_hash_name.include?(STAT_TRACK_MARKER)
    souvenir = market_hash_name.include?(SOUVENIR_MARKER)

    clean_name = market_hash_name.gsub(MARKERS_REGEXP, "")

    condition_match = clean_name.match(CONDITION_EXTRACT_REGEX)
    condition = condition_match ? condition_match[1] : nil

    clean_name = clean_name.gsub(CONDITION_CLEANUP_REGEX, "")

    if clean_name.include?(WEAPON_TYPE_SEPARATOR)
      weapon_type, item_name = clean_name.split(WEAPON_TYPE_SEPARATOR, 2)

      {
        market_hash_name:,
        metadata: {
          weapon_type:,
          item_name:,
          condition:,
          stattrak:,
          souvenir:,
          icon_url:,
          marketable:,
          tradable:,
          rarity:,
          category:
        }
      }
    else
      {
        market_hash_name:,
        metadata: {
          weapon_type: nil,
          condition: nil,
          item_name: clean_name,
          stattrak:,
          souvenir:,
          icon_url:,
          marketable:,
          tradable:,
          rarity:,
          category:
        }
      }
    end
  end

  sig { params(market_hash_names: T::Array[String]).returns(T::Array[ItemDto]) }
  def self.parse_collection(market_hash_names)
    market_hash_names.map { |name| parse(name) }
  end
end
