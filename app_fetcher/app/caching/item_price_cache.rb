# typed: strict

class ItemPriceCache
  extend T::Sig

  CACHE_KEY_VERSION = T.let(1, Integer)
  SAFETY_NET_TTL = T.let(15.minutes, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(market_hash_names: T::Array[String]).returns(T::Hash[String, Item]) }
    def fetch_for(market_hash_names)
      keys_by_name = market_hash_names.index_by { |name| cache_key(name) }
      cached = Rails.cache.read_multi(*keys_by_name.keys)

      missing_names = keys_by_name.reject { |key, _name| cached.key?(key) }.values

      if missing_names.any?
        found_items = Item.where(market_hash_name: missing_names).index_by(&:market_hash_name)

        to_write = T.let({}, T::Hash[T::Array[T.any(String, Integer)], Item])
        missing_names.each do |name|
          item = found_items[name]
          next unless item

          to_write[cache_key(name)] = item
        end

        Rails.cache.write_multi(to_write, expires_in: SAFETY_NET_TTL) if to_write.any?
        cached.merge!(to_write)
      end

      keys_by_name.each_with_object({}) do |(key, name), result|
        item = cached[key]
        result[name] = item if item
      end
    end

    sig { params(market_hash_name: String).void }
    def invalidate(market_hash_name)
      Rails.cache.delete(cache_key(market_hash_name))
    end

    private

    sig { params(market_hash_name: String).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(market_hash_name)
      [ "item_price", CACHE_KEY_VERSION, market_hash_name ]
    end
  end
end
