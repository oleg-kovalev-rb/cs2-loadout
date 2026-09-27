# typed: strict

class PriceHistoryCache
  extend T::Sig

  PricePoint = T.type_alias { { at: String, price_cents: Integer, volume: Integer } }

  CACHE_KEY_VERSION = T.let(1, Integer)
  SAFETY_NET_TTL = T.let(15.minutes, ActiveSupport::Duration)
  DEFAULT_WINDOW = T.let(30.days, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(market_hash_names: T::Array[String]).returns(T::Hash[String, T::Array[PricePoint]]) }
    def fetch_for(market_hash_names)
      keys_by_name = market_hash_names.index_by { |name| cache_key(name) }
      cached = Rails.cache.read_multi(*keys_by_name.keys)

      missing_names = keys_by_name.reject { |key, _name| cached.key?(key) }.values

      if missing_names.any?
        items_by_name = Item.where(market_hash_name: missing_names).index_by(&:market_hash_name)

        logs_by_item_id = PriceLog.where(item_id: items_by_name.values.map(&:id), created_at: DEFAULT_WINDOW.ago..)
                                   .order(:created_at)
                                   .group_by(&:item_id)

        to_write = T.let({}, T::Hash[T::Array[T.any(String, Integer)], T::Array[PricePoint]])
        missing_names.each do |name|
          item = items_by_name[name]
          next unless item

          points = (logs_by_item_id[item.id] || []).map do |log|
            { at: log.created_at.iso8601, price_cents: log.lowest_price_cents, volume: log.volume }
          end

          to_write[cache_key(name)] = points
        end

        Rails.cache.write_multi(to_write, expires_in: SAFETY_NET_TTL) if to_write.any?
        cached.merge!(to_write)
      end

      keys_by_name.each_with_object({}) do |(key, name), result|
        points = cached[key]
        result[name] = points if points
      end
    end

    sig { params(market_hash_name: String).void }
    def invalidate(market_hash_name)
      Rails.cache.delete(cache_key(market_hash_name))
    end

    private

    sig { params(market_hash_name: String).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(market_hash_name)
      [ "price_history", CACHE_KEY_VERSION, market_hash_name ]
    end
  end
end
