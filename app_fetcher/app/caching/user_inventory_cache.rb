# typed: strict

# Single-key read-through + invalidation: freshness now comes from the
# weekly UserInventorySyncService-driven sync plus manual refresh, which
# both call .invalidate right after UserInventory.sync! succeeds (see
# .claude/styleguides/fetcher/caching.md). This class only shields
# Postgres from a read on every dashboard render.
class UserInventoryCache
  extend T::Sig

  CACHE_KEY_VERSION = T.let(2, Integer)
  SAFETY_NET_TTL = T.let(15.minutes, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(T.nilable(T::Array[Item])) }
    def fetch(steam_id)
      Rails.cache.fetch(cache_key(steam_id), expires_in: SAFETY_NET_TTL, skip_nil: true) do
        user_inventory = UserInventory.find_by(steam_id: steam_id)
        user_inventory&.items&.to_a
      end
    end

    sig { params(steam_id: String).void }
    def invalidate(steam_id)
      Rails.cache.delete(cache_key(steam_id))
    end

    private

    sig { params(steam_id: String).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(steam_id)
      [ "user_inventory", CACHE_KEY_VERSION, steam_id ]
    end
  end
end
