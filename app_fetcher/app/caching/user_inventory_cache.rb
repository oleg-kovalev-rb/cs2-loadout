# typed: strict

# TTL-only, unlike ItemPriceCache/PriceHistoryCache: a user's Steam
# inventory changes because of their own trading activity on Steam, not
# because of anything this app writes — there is no write path in this
# app to hook an explicit `.invalidate` into, so staleness is bounded by
# TTL alone.
class UserInventoryCache
  extend T::Sig

  CACHE_KEY_VERSION = T.let(1, Integer)
  TTL = T.let(5.minutes, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(T.nilable(T::Array[String])) }
    def read(steam_id)
      Rails.cache.read(cache_key(steam_id))
    end

    sig { params(steam_id: String, market_hash_names: T::Array[String]).void }
    def write(steam_id, market_hash_names)
      Rails.cache.write(cache_key(steam_id), market_hash_names, expires_in: TTL)
    end

    private

    sig { params(steam_id: String).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(steam_id)
      [ "user_inventory", CACHE_KEY_VERSION, steam_id ]
    end
  end
end
