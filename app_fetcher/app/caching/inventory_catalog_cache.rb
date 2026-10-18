# typed: strict

require "digest"

class InventoryCatalogCache
  extend T::Sig

  CACHE_KEY_VERSION = T.let(2, Integer)
  TTL = T.let(2.minutes, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(params: ActionController::Parameters).returns(T.untyped) }
    def read(params)
      Rails.cache.read(cache_key(params))
    end

    sig { params(params: ActionController::Parameters, value: T.untyped).void }
    def write(params, value)
      Rails.cache.write(cache_key(params), value, expires_in: TTL)
    end

    private

    sig { params(params: ActionController::Parameters).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(params)
      normalized = {
        page: params[:page].to_s,
        per_page: params[:per_page].to_s,
        sort: params[:sort].to_s
      }
      [ "inventories_catalog", CACHE_KEY_VERSION, Digest::SHA256.hexdigest(normalized.to_json) ]
    end
  end
end
