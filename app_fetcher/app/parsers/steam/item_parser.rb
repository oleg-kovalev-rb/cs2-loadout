# typed: strict

module Steam
  class ItemParser
    extend T::Sig

    STAT_TRACK_MARKER = "StatTrak™"
    SOUVENIR_MARKER = "Souvenir"
    WEAPON_TYPE_SEPARATOR = " | "

    MARKERS_REGEXP = /StatTrak™\s*|Souvenir\s*/
    CONDITION_EXTRACT_REGEX = /\((.+?)\)$/.freeze
    CONDITION_CLEANUP_REGEX = /\s*\(.+?\)$/.freeze

    ItemDto = T.type_alias do
      {
        market_hash_name: String,
        metadata: {
          weapon_type: T.nilable(String),
          item_name: String,
          condition: T.nilable(String),
          stattrak: T::Boolean,
          souvenir: T::Boolean
        }
      }
    end

    sig { params(market_hash_name: String).returns(ItemDto) }
    def self.parse(market_hash_name)
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
            souvenir:
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
            souvenir:
          }
        }
      end
    end

    sig { params(market_hash_names: T::Array[String]).returns(T::Array[ItemDto]) }
    def self.parse_collection(market_hash_names)
      market_hash_names.map { |name| parse(name) }
    end
  end
end
