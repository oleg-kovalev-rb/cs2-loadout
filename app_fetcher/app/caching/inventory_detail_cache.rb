# typed: strict

require "digest"

class InventoryDetailCache
  extend T::Sig

  CACHE_KEY_VERSION = T.let(2, Integer)
  TTL = T.let(2.minutes, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(steam_id: String, params: ActionController::Parameters).returns(T.untyped) }
    def read(steam_id, params)
      Rails.cache.read(cache_key(steam_id, params))
    end

    sig { params(steam_id: String, params: ActionController::Parameters, value: T.untyped).void }
    def write(steam_id, params, value)
      Rails.cache.write(cache_key(steam_id, params), value, expires_in: TTL)
    end

    private

    sig { params(steam_id: String, params: ActionController::Parameters).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(steam_id, params)
      normalized = {
        range: params[:range].to_s,
        items_page: params[:items_page].to_s,
        items_per_page: params[:items_per_page].to_s,
        items_sort: params[:items_sort].to_s
      }
      [ "inventory_detail", CACHE_KEY_VERSION, steam_id, Digest::SHA256.hexdigest(normalized.to_json) ]
    end
  end
end
