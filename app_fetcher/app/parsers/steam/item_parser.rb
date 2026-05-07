# app/services/steam/item_parser.rb
# typed: strict

module Steam
  class ItemParser
    extend T::Sig

    sig { params(market_hash_name: String).returns(Item) }
    def self.parse(market_hash_name)
      item = Item.find_or_initialize_by(market_hash_name: market_hash_name)

      return item if item.persisted?

      item.metadata = get_metadata(market_hash_name)
      item
    end

    sig { params(market_hash_names: T::Array[String]).returns(T::Array[Item]) }
    def self.parse_collection(market_hash_names)
      market_hash_names.map { |name| parse(name) }
    end

    private

    def get_metadata(market_hash_name)
      stattrak = market_hash_name.include?("StatTrak™")
      souvenir = market_hash_name.include?("Souvenir")

      clean_name = market_hash_name.gsub(/StatTrak™\s*|Souvenir\s*/, '')

      condition_match = clean_name.match(/\((.+?)\)$/)
      condition = condition_match ? condition_match[1] : nil

      clean_name = clean_name.gsub(/\s*\(.+?\)$/, '')

      if clean_name.include?(" | ")
        weapon_type, item_name = clean_name.split(" | ", 2)

        {
          weapon_type: weapon_type,
          item_name: item_name,
          condition: condition,
          stattrak: stattrak,
          souvenir: souvenir
        }
      else
        {
          item_name: clean_name,
          condition: nil,
          stattrak: false,
          souvenir: false
        }
      end
    end
  end
end
