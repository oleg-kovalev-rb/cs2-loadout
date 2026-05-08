# typed: strict

module Steam
  class ItemParser
    extend T::Sig

    ParsedData = T.type_alias { T::Hash[Symbol, T.untyped] }

    sig { params(market_hash_name: String).returns(ParsedData) }
    def self.parse(market_hash_name)
      stattrak = market_hash_name.include?("StatTrak™")
      souvenir = market_hash_name.include?("Souvenir")

      clean_name = market_hash_name.gsub(/StatTrak™\s*|Souvenir\s*/, "")

      condition_match = clean_name.match(/\((.+?)\)$/)
      condition = condition_match ? condition_match[1] : nil

      clean_name = clean_name.gsub(/\s*\(.+?\)$/, "")

      if clean_name.include?(" | ")
        weapon_type, item_name = clean_name.split(" | ", 2)

        {
          market_hash_name: market_hash_name,
          metadata: {
            weapon_type: weapon_type,
            item_name: item_name,
            condition: condition,
            stattrak: stattrak,
            souvenir: souvenir
          }
        }
      else
        {
          market_hash_name: market_hash_name,
          metadata: {
            item_name: clean_name,
            condition: nil,
            stattrak: false,
            souvenir: false
          }
        }
      end
    end
  end
end
